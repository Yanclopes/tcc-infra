# =====================================================================
# State backend — S3 + DynamoDB (criados pelo infra/bootstrap/).
#
# Configuracao PARCIAL: bucket e dynamodb_table sao passados no init
# via -backend-config, permitindo que o mesmo codigo funcione em
# ambientes distintos (prod, staging) sem edicao do arquivo.
#
# No workflow do GitHub Actions:
#   terraform init \
#     -backend-config="bucket=$TF_STATE_BUCKET" \
#     -backend-config="dynamodb_table=$TF_LOCK_TABLE"
#
# Localmente (raro — o padrao e passar tudo pelo CI):
#   terraform init \
#     -backend-config="bucket=$(cd ../../bootstrap && terraform output -raw state_bucket)" \
#     -backend-config="dynamodb_table=$(cd ../../bootstrap && terraform output -raw state_lock_table)"
# =====================================================================

terraform {
  backend "s3" {
    key     = "prod/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
    # bucket e dynamodb_table vem via -backend-config no init
  }
}
