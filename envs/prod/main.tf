module "network" {
  source = "../../modules/network"

  name_prefix = "desafio-ods"
  vpc_cidr    = "10.0.0.0/16"
  subnet_cidr = "10.0.1.0/24"
  admin_ip    = var.admin_ip
}

module "compute" {
  source = "../../modules/compute"

  name_prefix       = "desafio-ods"
  subnet_id         = module.network.public_subnet_id
  security_group_id = module.network.app_security_group_id
  ssh_public_key    = var.ssh_public_key

  # Segredos e config passados ao bootstrap
  jwt_secret       = var.jwt_secret
  admin_email      = var.admin_email
  admin_password   = var.admin_password
  db_password      = var.db_password
  cors_origins     = var.cors_origins
  backend_repo_url = var.backend_repo_url
  backend_repo_ref = var.backend_repo_ref
}
