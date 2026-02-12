terraform {
  required_version = ">= 1.3.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

resource "random_id" "deployment" {
  byte_length = 4
}

module "network" {
  source = "./modules/network"

  deployment_id       = random_id.deployment.hex
  vpc_cidr            = var.vpc_cidr
  public_subnet_cidr  = var.public_subnet_cidr
  private_subnet_cidr = var.private_subnet_cidr
  database_subnet_cidr = var.database_subnet_cidr
  aws_region          = var.aws_region
}

module "dns" {
  source = "./modules/dns"

  deployment_id = random_id.deployment.hex
  vpc_id        = module.network.vpc_id
  web_server_ip = module.compute.web_private_ip
  api_server_ip = module.compute.api_private_ip
  db_server_ip  = module.compute.db_private_ip
}

module "compute" {
  source = "./modules/compute"

  deployment_id       = random_id.deployment.hex
  aws_region          = var.aws_region
  admin_username      = var.admin_username

  public_subnet_id    = module.network.public_subnet_id
  private_subnet_id   = module.network.private_subnet_id
  database_subnet_id  = module.network.database_subnet_id

  bastion_sg_id       = module.network.bastion_sg_id
  web_sg_id           = module.network.web_sg_id
  api_sg_id           = module.network.api_sg_id
  db_sg_id            = module.network.db_sg_id

  vpc_id              = module.network.vpc_id
}
