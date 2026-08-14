variable "aws_region" {
  description = "Regiao AWS onde tudo sera provisionado."
  type        = string
  default     = "us-east-1"
}

variable "admin_ip" {
  description = "IP publico do administrador (para permitir SSH). Use 'X.X.X.X/32' para um IP fixo. NUNCA use 0.0.0.0/0 em producao."
  type        = string
}

variable "ssh_public_key" {
  description = "Chave SSH publica (formato ssh-ed25519 AAAA... ou ssh-rsa AAAA...) para acessar o EC2."
  type        = string
}

# ---------- Segredos da aplicacao (baked no user_data no primeiro boot) ----------

variable "jwt_secret" {
  description = "JWT_SECRET forte para assinar tokens em producao. Gere com: openssl rand -base64 48"
  type        = string
  sensitive   = true
}

variable "admin_email" {
  description = "E-mail do usuario master inicial (criado pela seed)."
  type        = string
  default     = "admin@desafio-ods.local"
}

variable "admin_password" {
  description = "Senha do usuario master inicial. Gere uma senha forte. Troque no primeiro login."
  type        = string
  sensitive   = true
}

variable "db_password" {
  description = "Senha do Postgres rodando em docker dentro do EC2. Gere com: openssl rand -base64 32"
  type        = string
  sensitive   = true
}

variable "cors_origins" {
  description = "Origens permitidas no CORS, separadas por virgula. Ex.: 'https://desafio-ods.example.com'."
  type        = string
}

variable "backend_repo_url" {
  description = "URL HTTPS do repositorio do backend (usada no git clone via user_data)."
  type        = string
  default     = "https://github.com/Yanclopes/tcc-backend.git"
}

variable "backend_repo_ref" {
  description = "Branch, tag ou SHA do backend a fazer checkout."
  type        = string
  default     = "master"
}
