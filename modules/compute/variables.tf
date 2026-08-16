variable "name_prefix" {
  description = "Prefixo para nomes de recursos."
  type        = string
}

variable "instance_type" {
  description = "Tipo da instancia EC2 (t3.micro esta no free tier por 12 meses)."
  type        = string
  default     = "t3.micro"
}

variable "root_volume_size" {
  description = "Tamanho do disco raiz em GB (30GB e o teto do free tier gp3)."
  type        = number
  default     = 30
}

variable "subnet_id" {
  description = "Subnet onde a instancia sera criada."
  type        = string
}

variable "security_group_id" {
  description = "Security group a aplicar na instancia."
  type        = string
}

variable "ssh_public_key" {
  description = "Chave SSH publica para acesso."
  type        = string
}

# ---------- Passados ao bootstrap (user_data) ----------

variable "jwt_secret" {
  type      = string
  sensitive = true
}

variable "admin_email" {
  type = string
}

variable "admin_password" {
  type      = string
  sensitive = true
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "metrics_user" {
  description = "Usuario Basic Auth para o endpoint /metrics."
  type        = string
  default     = "metrics"
}

variable "metrics_password" {
  description = "Senha Basic Auth para o endpoint /metrics."
  type        = string
  sensitive   = true
}

# ---------- Grafana Cloud (Alloy remote_write) ----------

variable "grafana_cloud_metrics_url" {
  description = "URL de remote_write do Prometheus hospedado no Grafana Cloud (ex.: https://prometheus-prod-XX-prod-YY.grafana.net/api/prom/push)."
  type        = string
  default     = ""
}

variable "grafana_cloud_metrics_user" {
  description = "Instance ID (usuario) do stack Grafana Cloud usado no Basic Auth do remote_write."
  type        = string
  default     = ""
}

variable "grafana_cloud_metrics_api_key" {
  description = "API key (glc_...) do stack Grafana Cloud usado como senha no remote_write. Rotacionavel em Access Policies."
  type        = string
  default     = ""
  sensitive   = true
}

variable "cors_origins" {
  type = string
}

variable "backend_repo_url" {
  type = string
}

variable "backend_repo_ref" {
  type = string
}
