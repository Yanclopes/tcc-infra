# infra/ — Terraform para o Desafio ODS

Provisiona a infraestrutura do backend na AWS. Arquitetura de custo mínimo com **fluxo de duas fases** (bootstrap local uma vez + tudo mais via GitHub Actions).

```
  ┌──────────────────────┐        ┌────────────────────────────────┐
  │   Cloudflare (free)  │───────▶│  EC2 t3.micro  (Ubuntu 22.04)  │
  │   DNS + CDN + WAF    │  HTTP  │  ┌──────────┐  ┌──────────┐   │
  └──────────────────────┘        │  │ postgres │  │  redis   │   │
             ▲                    │  └──────────┘  └──────────┘   │
             │                    │  ┌──────────────────────────┐ │
   ┌─────────────────────┐        │  │ api (imagem GHCR :master)│ │
   │ Cloudflare Pages    │        │  └──────────────────────────┘ │
   │ (frontend estatico) │        │      docker compose prod      │
   └─────────────────────┘        └────────────────────────────────┘
```

**Custo estimado** (região `us-east-1`):

| Item | Free tier (12 meses) | Após free tier |
| --- | --- | --- |
| EC2 t3.micro (24/7) | $0 (750h/mês) | ~$7,60/mês |
| EBS gp3 30GB | $0 (30GB grátis) | ~$2,40/mês |
| Elastic IP (IPv4 público) | $0 (750h/mês grátis) | ~$3,65/mês |
| S3 tfstate + DynamoDB lock | $0 (dentro do free tier permanente) | ~$0 |
| Data transfer OUT | $0 (100GB/mês grátis) | $0 no piloto acadêmico |
| **Total AWS** | **$0/mês** | **~US$ 13,65/mês (~R$ 70)** |

Cloudflare (DNS + CDN + WAF + Pages) e GHCR (imagens Docker) são grátis para sempre no plano Free.

## Estrutura

```
infra/
├── .terraform-version         Terraform 1.9.8+
├── .gitignore                 bloqueia *.tfstate, terraform.tfvars, *.pem
├── .github/workflows/
│   └── terraform.yml          CI: plan em PR, apply em push master (com Environment protection)
├── bootstrap/                 rodado UMA VEZ, LOCALMENTE (não vai pro CI)
│   ├── main.tf                IAM CI user + S3 (tfstate) + DynamoDB (lock)
│   ├── providers.tf
│   ├── variables.tf
│   ├── outputs.tf             credenciais e nomes para cadastrar como GitHub Secrets
│   └── README.md
└── envs/prod/                 aplicado pelo CI (nunca manualmente após bootstrap)
    ├── providers.tf
    ├── backend.tf             S3 backend (config parcial — bucket/table via -backend-config)
    ├── variables.tf
    ├── main.tf                compõe modules/network + modules/compute
    ├── outputs.tf             public_ip, ssh_command, api_url
    └── terraform.tfvars.example  (só documenta os TF_VAR_* — no CI vêm de Secrets)
└── modules/
    ├── network/               VPC + subnet pública única + IGW + SG
    └── compute/               EC2 t3.micro Ubuntu 22.04 + EIP + user-data
```

## Visão geral do fluxo

```
1x LOCAL (você):                       CI (GitHub Actions, sempre):
────────────────────                   ───────────────────────────────
cd infra/bootstrap                     push em tcc-infra
terraform init                         → terraform plan/apply
terraform apply                        → provisiona EC2 + rede
   │
   ↓
IAM user + S3 + DynamoDB               push em tcc-backend
   │                                   → CI (lint + test + e2e)
   ↓                                   → build imagem Docker
Copia access key e nomes               → push GHCR :master + :sha
para GitHub Secrets                    → SSH no EC2
                                       → docker compose pull + up
                                       → migration:run
```

## Fase 1 — Bootstrap local (uma vez)

### Pré-requisitos

- **Terraform ≥ 1.9** — https://developer.hashicorp.com/terraform/install
- **AWS CLI** com credenciais do seu próprio usuário — https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
- **Chave SSH** para acessar o EC2 depois:
  ```bash
  ssh-keygen -t ed25519 -C "desafio-ods"   # se ainda não tem
  ```

### Passos

```bash
# 1. Configurar AWS CLI com seu usuário admin
aws configure   # cole access key + secret + região us-east-1

# 2. Rodar bootstrap
cd infra/bootstrap
terraform init
terraform apply    # cria S3 + DynamoDB + IAM CI user

# 3. Ver outputs
terraform output
terraform output -raw ci_secret_access_key   # sensitive, exibir separado
```

Saída típica (a marcação `next_steps` do bootstrap já lista tudo):

```
ci_access_key_id  = "AKIAXXXXXXXXXXXXXXXX"
state_bucket      = "desafio-ods-tfstate-a1b2c3d4"
state_lock_table  = "desafio-ods-tflock"
```

## Fase 2 — Configurar GitHub Secrets (uma vez)

Após o bootstrap, no repositório **`tcc-infra`** (Settings → Secrets and variables → Actions):

### Secrets do provedor (do bootstrap)

| Nome | Valor |
| --- | --- |
| `AWS_ACCESS_KEY_ID` | `terraform output ci_access_key_id` |
| `AWS_SECRET_ACCESS_KEY` | `terraform output -raw ci_secret_access_key` |
| `TF_STATE_BUCKET` | `terraform output state_bucket` |
| `TF_LOCK_TABLE` | `terraform output state_lock_table` |

### Secrets da aplicação (você define)

| Nome | Como gerar/obter |
| --- | --- |
| `TF_VAR_admin_ip` | `curl ifconfig.me` → `X.X.X.X/32` |
| `TF_VAR_ssh_public_key` | `cat ~/.ssh/id_ed25519.pub` |
| `TF_VAR_jwt_secret` | `openssl rand -base64 48` |
| `TF_VAR_admin_password` | `openssl rand -base64 24` |
| `TF_VAR_db_password` | `openssl rand -base64 32` |
| `TF_VAR_admin_email` | seu e-mail |
| `TF_VAR_cors_origins` | ex.: `https://desafio-ods.pages.dev,https://api.seu-dominio.com` |

Além dos secrets, criar o **Environment `production`** (Settings → Environments) com **Required reviewers = você**. O workflow pausa aguardando aprovação antes de aplicar em prod.

## Fase 3 — Deploy do infra via push

```bash
cd infra
git init   # se ainda não é repo
gh repo create Yanclopes/tcc-infra --private --source . --push
```

O workflow `.github/workflows/terraform.yml` roda:

- **em PR**: `terraform plan` (mostra diff sem aplicar).
- **em push `master`**: `terraform plan` → aguarda aprovação → `apply`.

Após o `apply`, o output `public_ip` mostra o IP do EC2. Copie.

## Fase 4 — Publicar imagem e deploy no tcc-backend

### 4.1 Setup dos Secrets no tcc-backend

No repo **`tcc-backend`** (Settings → Secrets/Variables):

Secrets:

| Nome | Valor |
| --- | --- |
| `EC2_HOST` | IP do EC2 (do output do Terraform) |
| `EC2_SSH_KEY` | `cat ~/.ssh/id_ed25519` (chave PRIVADA — o correspondente da pública que você passou pro Terraform) |

Variables (Repository variables):

| Nome | Valor |
| --- | --- |
| `DEPLOY_ENABLED` | `true` |

### 4.2 Como funciona

O workflow `tcc-backend/.github/workflows/publish-and-deploy.yml` já está pronto. A cada push em `master`:

1. `build-and-push` — builda a imagem Docker no runner do GitHub Actions (não no EC2!), envia pra **`ghcr.io/yanclopes/tcc-backend:master`** e **`:sha-abc123`**.
2. `deploy` — SSH no EC2, `docker compose -f docker-compose.prod.yml pull api`, `up -d`, roda `migration:run:prod`.

**Primeiro push depois do infra apply**: o EC2 já bootou e puxou a imagem via user_data. O deploy do CI faz o mesmo fluxo mas incremental.

## Fase 5 — Cloudflare (DNS + CDN + WAF, grátis)

Se seu domínio ainda não está na Cloudflare, mover:

1. Cloudflare → Add Site → digite seu domínio → plano **Free**.
2. No seu registrar, substitua os nameservers pelos da Cloudflare.
3. Aguarde propagação.

Depois:

- **DNS** → Add record: `A` name=`api` value=`<EIP do terraform>`, **Proxy ativo (laranja)**.
- **SSL/TLS** → Overview → modo **Flexible** (Cloudflare termina HTTPS; conversa HTTP com o EC2).
- **Cache Rules**: `api.seu-dominio.com/*` → Cache Level **Bypass**.
- **Origin Rules** → Override Destination Port: Host `api.seu-dominio.com` → porta `3000`.

## Fase 6 — Frontend no Cloudflare Pages (grátis)

1. Cloudflare → Workers & Pages → Pages → Connect to Git → repo `Yanclopes/tcc-frontend`.
2. Framework: Vite. Build: `npm run build`. Output: `dist`.
3. Env var: `VITE_API_URL = https://api.seu-dominio.com/api/v1`.
4. Deploy automático a cada push em `master`.

## Operação

### Ver logs em produção

```bash
ssh ubuntu@<eip>
cd /opt/desafio-ods
docker compose -f docker-compose.prod.yml logs -f api
```

### Rollback

O último SHA está sempre disponível no GHCR (`:sha-abc123`). Para reverter:

```bash
ssh ubuntu@<eip>
cd /opt/desafio-ods
# edita docker-compose.prod.yml, troca :master pela :sha-ANTERIOR
docker compose -f docker-compose.prod.yml up -d api
```

Ou reverte o commit no `tcc-backend` que quebrou e o CD reaplica automaticamente.

### Backup do Postgres (workaround — sem RDS)

```bash
ssh ubuntu@<eip>
docker compose -f docker-compose.prod.yml exec -T postgres pg_dump -U ods ods_quiz | gzip > ~/ods-backup-$(date +%F).sql.gz
scp ubuntu@<eip>:~/ods-backup-*.sql.gz .
```

Automatizar com cron + upload S3 é a evolução natural (S3 free tier: 5GB).

> **Restore com pgvector**: desde a introdução do assistente de IA, o banco usa
> a extensão `vector` e a tabela `chat_trecho` tem coluna `vector(1536)`. Um
> dump que contenha essa coluna **só restaura num Postgres que tenha a extensão
> instalada** — use a imagem `pgvector/pgvector:pg16`, não a `postgres:16-alpine`.

### Migração do Postgres para a imagem com pgvector

Necessária uma única vez, para habilitar o assistente de IA. **Não troque a
imagem sobre o volume existente.**

A imagem antiga (`postgres:16-alpine`) é baseada em musl; a do pgvector é
Debian/glibc, e o pgvector não publica variante Alpine. As duas libcs ordenam
texto de forma diferente, e índices btree sobre texto são construídos na ordem
da collation. Trocar a imagem mantendo o volume deixa os índices inconsistentes
**sem gerar erro** — apenas deixando de encontrar linhas que existem. Há 7
índices nessa condição no schema, sendo dois críticos: `app_user_email_key`
(UNIQUE em e-mail) e `game_pkey` (PK sobre UUID).

O procedimento correto é dump e restore em volume novo, o que reconstrói os
índices sob a nova collation:

```bash
ssh ubuntu@<eip>
cd ~/tcc-backend

# 1. Backup verificado (confira o número de tabelas antes de prosseguir)
docker compose -f docker-compose.prod.yml exec -T postgres \
  pg_dump -U ods --no-owner --no-acl ods_quiz > ~/pre-pgvector.sql
grep -c '^CREATE TABLE' ~/pre-pgvector.sql

# 2. Derruba e descarta o volume ANTIGO (nomeie explicitamente; não use down -v)
docker compose -f docker-compose.prod.yml down
docker volume rm tcc-backend_postgres_data

# 3. Sobe a imagem nova (já apontada no compose) e restaura
docker compose -f docker-compose.prod.yml up -d postgres
gunzip -c ~/pre-pgvector.sql 2>/dev/null || cat ~/pre-pgvector.sql | \
  docker compose -f docker-compose.prod.yml exec -T postgres psql -U ods -d ods_quiz

# 4. Confere e sobe o resto
docker compose -f docker-compose.prod.yml exec -T postgres \
  psql -U ods -d ods_quiz -c "select version();" -c "\\dt"
docker compose -f docker-compose.prod.yml up -d
```

Depois disso, rode a migration e a indexação:

```bash
docker compose -f docker-compose.prod.yml exec -T api npm run migration:run:prod
docker compose -f docker-compose.prod.yml exec -T api npm run chat:indexar:prod
```

A indexação exige `OPENAI_API_KEY` no `.env` do EC2. Sem ela o módulo de chat
sobe desabilitado (rotas respondem 503) e o resto da plataforma segue normal.

### Destruir tudo

```bash
# Primeiro o env de aplicação
cd infra/envs/prod
terraform init -backend-config="bucket=$(cd ../../bootstrap && terraform output -raw state_bucket)" \
               -backend-config="dynamodb_table=$(cd ../../bootstrap && terraform output -raw state_lock_table)"
terraform destroy

# Depois (opcional) o bootstrap
cd ../../bootstrap
terraform destroy    # ATENÇÃO: apaga o histórico do tfstate!
```

## Trade-offs conhecidos (workarounds)

| Decisão | Alternativa gerenciada | Motivo |
| --- | --- | --- |
| **Postgres em Docker no EC2** | RDS PostgreSQL | Free tier tem RDS db.t3.micro grátis por 12 meses (~$13/mês depois). Escolhemos in-VM para custo mínimo pós-free-tier; sem backup automático (fazer via cron). |
| **Redis em Docker no EC2** | ElastiCache Redis | ElastiCache não tem free tier (~$12/mês). Escolhemos in-VM para zerar custo. |
| **Subnet pública única** | Subnet privada + NAT Gateway | NAT Gateway custa ~$30/mês só por existir. Instância na subnet pública tem IP direto. |
| **Access keys long-lived** | OIDC + IAM role trust | OIDC é a prática correta (sem chaves rotacionáveis). Fica para migração posterior — access keys funcionam bem para começar. |
| **CD via SSH + docker pull** | ECS/K8s com rolling update | Simples, funciona, sem custo adicional. Rolling update true não existe (há downtime de ~5s). |

## O que ainda falta

- Migrar `AWS_ACCESS_KEY_ID`/`SECRET` para **OIDC** (autenticação sem chaves long-lived).
- **Observabilidade** (logs estruturados + `/metrics`) — [.specs/02-infra/07-observabilidade.md](../.specs/02-infra/07-observabilidade.md).
- **GitOps completo** (Atlantis ou Terraform Cloud com plan comment em PR) — [.specs/02-infra/05-gitops.md](../.specs/02-infra/05-gitops.md).
- **Backup automatizado** do Postgres para S3 via cron.
