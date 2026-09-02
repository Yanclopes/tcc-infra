module "network" {
  source = "../../modules/network"

  name_prefix = "desafio-ods"
  vpc_cidr    = "10.0.0.0/16"
  subnet_cidr = "10.0.1.0/24"
  admin_ip    = var.admin_ip
  app_port    = 3000
}

module "compute" {
  source = "../../modules/compute"

  name_prefix       = "desafio-ods"
  subnet_id         = module.network.public_subnet_id
  security_group_id = module.network.app_security_group_id
  ssh_public_key    = var.ssh_public_key

  # Segredos e config passados ao bootstrap
  jwt_secret                    = var.jwt_secret
  admin_email                   = var.admin_email
  admin_password                = var.admin_password
  db_password                   = var.db_password
  metrics_password              = var.metrics_password
  grafana_cloud_metrics_url     = var.grafana_cloud_metrics_url
  grafana_cloud_metrics_user    = var.grafana_cloud_metrics_user
  grafana_cloud_metrics_api_key = var.grafana_cloud_metrics_api_key
  cors_origins                  = var.cors_origins
  backend_repo_url              = var.backend_repo_url
  backend_repo_ref              = var.backend_repo_ref
}
