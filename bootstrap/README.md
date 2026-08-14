# infra/bootstrap/

Recursos criados **uma vez, localmente**, para viabilizar o resto do
Terraform rodar no GitHub Actions:

- **S3 bucket** para o `tfstate` (versionado + criptografado, sem acesso público).
- **DynamoDB table** para lock do state (evita `apply` concorrente).
- **IAM user** `desafio-ods-ci` com permissões escoped:
  - `AmazonEC2FullAccess` (EC2 + VPC + SG + EIP + KeyPair).
  - S3/DynamoDB restritos ao bucket e tabela deste bootstrap.

## Pré-requisitos

- AWS CLI configurado com credenciais do seu **próprio usuário** (não do CI):
  ```bash
  aws configure
  ```
- Terraform ≥ 1.9.

## Rodar

```bash
cd infra/bootstrap
terraform init
terraform apply
```

## Após o apply

```bash
# Ver os outputs (o secret é sensitive, use -raw pra copiar):
terraform output

# O ci_secret_access_key aparece como sensitive; pra ver:
terraform output -raw ci_secret_access_key
```

Copie os valores dos outputs e cadastre como **GitHub Secrets** no repo `tcc-infra`:

| Secret | Origem |
| --- | --- |
| `AWS_ACCESS_KEY_ID` | `terraform output ci_access_key_id` |
| `AWS_SECRET_ACCESS_KEY` | `terraform output -raw ci_secret_access_key` |
| `TF_STATE_BUCKET` | `terraform output state_bucket` |
| `TF_LOCK_TABLE` | `terraform output state_lock_table` |

Cadastre também os `TF_VAR_*` da aplicação (ver o output `next_steps`).

## Rodar novamente?

Só se algo mudar aqui (ex.: adicionar permissão no IAM user). O `apply`
é idempotente. Se recriar a `access_key`, precisa atualizar os GitHub Secrets.

## Destruir

```bash
terraform destroy
```

⚠️  **Atenção**: destruir o bucket apaga TODO o histórico de tfstate.
Rode `terraform destroy` no `envs/prod/` **primeiro** para tirar a stack de pé.
