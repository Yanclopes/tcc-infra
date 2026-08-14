output "ci_access_key_id" {
  description = "Access Key ID do usuario CI. Cadastre como GitHub Secret AWS_ACCESS_KEY_ID no repo tcc-infra."
  value       = aws_iam_access_key.ci.id
}

output "ci_secret_access_key" {
  description = "Secret Access Key. Cadastre como GitHub Secret AWS_SECRET_ACCESS_KEY no repo tcc-infra. NUNCA commite este valor."
  value       = aws_iam_access_key.ci.secret
  sensitive   = true
}

output "state_bucket" {
  description = "Bucket S3 do tfstate. Cadastre como GitHub Secret TF_STATE_BUCKET."
  value       = aws_s3_bucket.tfstate.id
}

output "state_lock_table" {
  description = "Tabela DynamoDB do lock. Cadastre como GitHub Secret TF_LOCK_TABLE."
  value       = aws_dynamodb_table.tflock.id
}

output "next_steps" {
  description = "Instrucoes pos-bootstrap."
  value       = <<-EOT

    ============================================================
    BOOTSTRAP CONCLUIDO. Proximos passos:

    1. Veja o secret com:
         terraform output -raw ci_secret_access_key

    2. No repo tcc-infra (Settings > Secrets and variables > Actions),
       cadastre os secrets abaixo:

       AWS_ACCESS_KEY_ID        = ${aws_iam_access_key.ci.id}
       AWS_SECRET_ACCESS_KEY    = (rode: terraform output -raw ci_secret_access_key)
       TF_STATE_BUCKET          = ${aws_s3_bucket.tfstate.id}
       TF_LOCK_TABLE            = ${aws_dynamodb_table.tflock.id}

    3. Cadastre tambem os TF_VAR_* com os valores da aplicacao:

       TF_VAR_admin_ip
       TF_VAR_ssh_public_key
       TF_VAR_jwt_secret
       TF_VAR_admin_password
       TF_VAR_db_password
       TF_VAR_admin_email
       TF_VAR_cors_origins

    4. Faca push do infra/envs/prod/... e o workflow do tcc-infra aplica.
    ============================================================
  EOT
}
