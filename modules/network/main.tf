# =====================================================================
# Rede minima: uma VPC, uma subnet publica em uma unica AZ, sem NAT.
# NAT Gateway custa ~$30/mes so por existir — evitamos deliberadamente
# usando apenas subnet publica (a instancia tem IP publico direto).
# =====================================================================

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.name_prefix}-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.name_prefix}-igw"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.name_prefix}-public"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.name_prefix}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# ---------------------------------------------------------------------
# Faixas de IP da Cloudflare, buscadas na fonte oficial.
#
# Nao ficam fixas no codigo de proposito: a Cloudflare acrescenta faixas de
# tempos em tempos, e uma lista velha aqui significa usuarios recebendo conexao
# recusada sem nenhum sinal no sistema. Buscando, um `terraform plan` mostra a
# mudanca no dia em que ela acontece.
#
# A contrapartida e que o plan passa a depender de alcancar cloudflare.com. A
# postcondition abaixo transforma uma resposta vazia ou truncada em erro de plan
# — falha barulhenta e sem efeito — em vez de um security group que bloqueia a
# Cloudflare inteira.
# ---------------------------------------------------------------------
data "http" "cloudflare_ipv4" {
  url = "https://www.cloudflare.com/ips-v4"

  lifecycle {
    postcondition {
      condition     = length(compact(split("\n", chomp(self.response_body)))) >= 10
      error_message = "Lista de IPv4 da Cloudflare veio com menos faixas do que o esperado; abortando para nao trancar a origem."
    }
  }
}

locals {
  cloudflare_ipv4 = compact(split("\n", chomp(data.http.cloudflare_ipv4.response_body)))
}

# ---------------------------------------------------------------------
# Security group: SSH restrito ao IP do admin; a porta da aplicacao aberta
# SOMENTE para a Cloudflare.
#
# Antes, 80, 443 e 3000 estavam abertas para 0.0.0.0/0. Duas consequencias:
#
#   1. Qualquer um alcancava a origem pelo IP publico e contornava por completo
#      o WAF e o rate limit da Cloudflare — havia registro disso nos logs.
#   2. O cabecalho `CF-Connecting-IP`, que a aplicacao usa para identificar o
#      usuario no rate limit, era forjavel por quem falasse direto com a origem.
#      Restringir aqui e o que torna aquele cabecalho confiavel.
#
# 80 e 443 foram removidas: nao ha nada escutando nelas (sem nginx, sem proxy
# reverso). A Cloudflare fala com a origem na 3000, via Origin Rule.
# ---------------------------------------------------------------------
resource "aws_security_group" "app" {
  name        = "${var.name_prefix}-app-sg"
  description = "SSH restrito ao admin; porta da aplicacao restrita a Cloudflare"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH restrito ao IP do admin"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_ip]
  }

  ingress {
    description = "Aplicacao - somente da borda da Cloudflare"
    from_port   = var.app_port
    to_port     = var.app_port
    protocol    = "tcp"
    cidr_blocks = local.cloudflare_ipv4
  }

  egress {
    description = "Saida irrestrita (necessario para docker pull, apt, git clone)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name_prefix}-app-sg"
  }
}
