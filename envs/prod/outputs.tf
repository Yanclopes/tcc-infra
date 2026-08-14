output "public_ip" {
  description = "IP publico permanente (Elastic IP) da instancia — use este para configurar o DNS na Cloudflare."
  value       = module.compute.public_ip
}

output "instance_id" {
  description = "Id da instancia EC2."
  value       = module.compute.instance_id
}

output "ssh_command" {
  description = "Comando pronto para SSH na instancia."
  value       = "ssh ubuntu@${module.compute.public_ip}"
}

output "api_url" {
  description = "URL provisoria da API (via IP publico direto). Aponte o dominio via Cloudflare para HTTPS."
  value       = "http://${module.compute.public_ip}:3000/api/v1"
}

output "health_url" {
  description = "URL do healthcheck. Aguarde alguns minutos apos o apply para o bootstrap completar."
  value       = "http://${module.compute.public_ip}:3000/health"
}

output "backup_bucket" {
  description = "Bucket S3 com os backups diarios do Postgres (retencao 7 dias)."
  value       = module.compute.backup_bucket
}
