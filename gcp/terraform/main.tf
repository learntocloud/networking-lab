terraform {
  required_version = ">= 1.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
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

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

resource "random_id" "deployment" {
  byte_length = 4
}

module "network" {
  source        = "./modules/network"
  project_id    = var.project_id
  region        = var.region
  deployment_id = random_id.deployment.hex
}

module "compute" {
  source        = "./modules/compute"
  project_id    = var.project_id
  region        = var.region
  zone          = var.zone
  deployment_id = random_id.deployment.hex

  vpc_self_link        = module.network.vpc_self_link
  public_subnet_link   = module.network.public_subnet_link
  private_subnet_link  = module.network.private_subnet_link
  database_subnet_link = module.network.database_subnet_link
}

module "dns" {
  source        = "./modules/dns"
  project_id    = var.project_id
  deployment_id = random_id.deployment.hex
  vpc_self_link = module.network.vpc_self_link

  web_server_ip = module.compute.web_server_private_ip
  api_server_ip = module.compute.api_server_private_ip
  db_server_ip  = module.compute.db_server_private_ip
}
