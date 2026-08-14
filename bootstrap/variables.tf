variable "aws_region" {
  description = "Regiao AWS para os recursos de bootstrap (S3 bucket e DynamoDB)."
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Prefixo dos recursos (bucket, tabela, usuario)."
  type        = string
  default     = "desafio-ods"
}
