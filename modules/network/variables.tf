variable "name_prefix" {
  description = "Prefixo para nomes de recursos."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR da VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR da subnet publica unica."
  type        = string
  default     = "10.0.1.0/24"
}

variable "admin_ip" {
  description = "IP autorizado a fazer SSH (formato X.X.X.X/32)."
  type        = string
}

variable "app_port" {
  description = "Porta em que a aplicacao escuta na origem e que a Cloudflare acessa."
  type        = number
  default     = 3000
}
