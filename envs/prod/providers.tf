terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    # Usado pelo modulo network para buscar as faixas de IP da Cloudflare.
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "desafio-ods"
      Env       = "prod"
      Owner     = "yan"
      ManagedBy = "terraform"
    }
  }
}
