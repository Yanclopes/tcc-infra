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

resource "aws_instance" "app" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [var.security_group_id]
  key_name               = aws_key_pair.admin.key_name

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
    cors_origins     = var.cors_origins
    backend_repo_url = var.backend_repo_url
    backend_repo_ref = var.backend_repo_ref
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
