# =====================================================================
# Instancia unica t3.micro rodando Ubuntu 22.04. Postgres, Redis e a
# API sobem via docker-compose no primeiro boot (ver user-data.sh.tpl).
# Custo: $0 nos primeiros 12 meses (free tier), ~US$ 13,65/mes depois
# (EC2 $7,60 + EBS 30GB $2,40 + IPv4 publico $3,65 — a mudanca de Fev/2024
# faz o EIP custar mesmo atachado).
# =====================================================================

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_key_pair" "admin" {
  key_name   = "${var.name_prefix}-admin"
  public_key = var.ssh_public_key
}

# =====================================================================
# IAM instance profile — permite que a instancia se registre no AWS SSM.
# Isso viabiliza deploy via `aws ssm send-command` (sem precisar de SSH
# aberto pro runner do GitHub Actions).
# O SSM agent ja vem pre-instalado na AMI do Ubuntu Canonical.
# =====================================================================
resource "aws_iam_role" "app" {
  name = "${var.name_prefix}-app-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "app_ssm" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "app" {
  name = "${var.name_prefix}-app-profile"
  role = aws_iam_role.app.name
}

# =====================================================================
# Backup do Postgres — bucket S3 privado com retencao de 7 dias.
# Cron no EC2 (setup no user-data) faz `pg_dump | gzip | aws s3 cp -`.
# =====================================================================
resource "random_id" "backups_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "backups" {
  bucket        = "${var.name_prefix}-db-backups-${random_id.backups_suffix.hex}"
  force_destroy = false

  tags = {
    Purpose = "postgres-backups"
  }
}

resource "aws_s3_bucket_public_access_block" "backups" {
  bucket                  = aws_s3_bucket.backups.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    id     = "expire-after-7-days"
    status = "Enabled"

    filter {
      prefix = ""
    }

    expiration {
      days = 7
    }

    # Limpa uploads incompletos rapidamente pra nao acumular custo.
    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

# Permissao pro EC2 gravar backups (escopo: so este bucket, so PutObject).
resource "aws_iam_role_policy" "app_backup" {
  name = "${var.name_prefix}-app-backup"
  role = aws_iam_role.app.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "PutBackupObjects"
      Effect   = "Allow"
      Action   = ["s3:PutObject"]
      Resource = "${aws_s3_bucket.backups.arn}/*"
    }]
  })
}

resource "aws_instance" "app" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [var.security_group_id]
  key_name               = aws_key_pair.admin.key_name
  iam_instance_profile   = aws_iam_instance_profile.app.name

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size
    delete_on_termination = true
    encrypted             = true
  }

  user_data = templatefile("${path.module}/user-data.sh.tpl", {
    jwt_secret       = var.jwt_secret
    admin_email      = var.admin_email
    admin_password   = var.admin_password
    db_password      = var.db_password
    metrics_user     = var.metrics_user
    metrics_password = var.metrics_password
    cors_origins     = var.cors_origins
    backend_repo_url = var.backend_repo_url
    backend_repo_ref = var.backend_repo_ref
    backup_bucket    = aws_s3_bucket.backups.id
  })
  # Trigger recreation da instancia se o template mudar (opcional).
  user_data_replace_on_change = false

  tags = {
    Name = "${var.name_prefix}-api"
  }

  # Evita recriar por causa de mudancas na AMI (o data.aws_ami retorna a mais recente).
  lifecycle {
    ignore_changes = [ami]
  }
}

# IP publico permanente — sobrevive a reboots e ate a recriacao da instancia.
# Enquanto associado a uma instancia rodando, o EIP e gratuito.
resource "aws_eip" "app" {
  instance = aws_instance.app.id
  domain   = "vpc"

  tags = {
    Name = "${var.name_prefix}-eip"
  }
}
