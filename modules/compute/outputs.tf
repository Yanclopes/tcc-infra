output "instance_id" {
  value = aws_instance.app.id
}

output "public_ip" {
  value = aws_eip.app.public_ip
}

output "private_ip" {
  value = aws_instance.app.private_ip
}

output "backup_bucket" {
  description = "Bucket S3 dos backups diarios do Postgres (retencao 7 dias)."
  value       = aws_s3_bucket.backups.id
}
