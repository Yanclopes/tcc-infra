#!/bin/bash
# =====================================================================
# Bootstrap do EC2 — roda uma vez, no primeiro boot da instancia.
# Log completo em /var/log/cloud-init-output.log.
#
# Instala Docker, clona o repo tcc-backend (so pelo compose file), gera
# .env com os segredos do Terraform, PUXA a imagem do GHCR e sobe os
# containers. Nao builda: a imagem vem pronta do CI do tcc-backend.
# Atualizacoes de codigo depois do bootstrap vem via CI (SSH + pull).
# =====================================================================
set -euxo pipefail

APP_DIR=/opt/desafio-ods
ENV_FILE=$APP_DIR/.env

# ---- 1. Sistema base ----
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
apt-get install -y ca-certificates curl gnupg git awscli

# ---- 2. Docker + docker compose plugin (repositorio oficial) ----
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Permite o usuario ubuntu rodar docker sem sudo (efetivo no proximo login)
usermod -aG docker ubuntu

# ---- 3. Clone do backend ----
mkdir -p $APP_DIR
git clone --branch ${backend_repo_ref} ${backend_repo_url} $APP_DIR
cd $APP_DIR

# ---- 4. .env gerado com os segredos passados via Terraform ----
cat > $ENV_FILE <<EOF
NODE_ENV=production
PORT=3000
API_PREFIX=api/v1
CORS_ORIGINS=${cors_origins}

DB_HOST=postgres
DB_PORT=5432
DB_USERNAME=ods
DB_PASSWORD=${db_password}
DB_DATABASE=ods_quiz
DB_SYNCHRONIZE=false
DB_LOGGING=false

REDIS_HOST=redis
REDIS_PORT=6379
REDIS_DB=0
GAME_SESSION_TTL=7200

JWT_SECRET=${jwt_secret}
JWT_EXPIRES_IN=1d

GAME_DEFAULT_POWERUPS=3

ADMIN_EMAIL=${admin_email}
ADMIN_PASSWORD=${admin_password}
EOF

chmod 600 $ENV_FILE
chown -R ubuntu:ubuntu $APP_DIR

# ---- 5. Puxa a imagem do GHCR e sobe os containers ----
# NAO builda: imagem vem pronta do GitHub Container Registry (workflow
# publish-and-deploy.yml do tcc-backend).
docker compose -f docker-compose.prod.yml pull
docker compose -f docker-compose.prod.yml up -d

# ---- 6. Aguarda a api ficar pronta e roda migrations + seed ----
for i in $(seq 1 30); do
  if docker compose -f docker-compose.prod.yml exec -T api node -e "process.exit(0)" >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

docker compose -f docker-compose.prod.yml exec -T api npm run migration:run:prod
docker compose -f docker-compose.prod.yml exec -T api npm run seed:prod

# ---- 7. Backup diario do Postgres para S3 (retencao 7 dias no bucket) ----
cat > /usr/local/bin/ods-backup.sh <<'BACKUP_EOF'
#!/bin/bash
set -euo pipefail
BUCKET="${backup_bucket}"
STAMP=$$(date -u +%Y%m%dT%H%M%SZ)
KEY="postgres/ods_quiz-$$STAMP.sql.gz"
cd /opt/desafio-ods
docker compose -f docker-compose.prod.yml exec -T postgres pg_dump -U ods ods_quiz \
  | gzip \
  | aws s3 cp - "s3://$$BUCKET/$$KEY"
echo "[$$(date -u +%FT%TZ)] backup enviado: s3://$$BUCKET/$$KEY"
BACKUP_EOF
chmod 755 /usr/local/bin/ods-backup.sh

# Cron diario as 03:00 UTC (~00:00 BRT)
cat > /etc/cron.d/ods-backup <<'CRON_EOF'
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
0 3 * * * root /usr/local/bin/ods-backup.sh >> /var/log/ods-backup.log 2>&1
CRON_EOF
chmod 644 /etc/cron.d/ods-backup

EIP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 || echo "unknown")
echo "Bootstrap concluido. API em http://$EIP:3000/api/v1 · backups em s3://${backup_bucket}/"
