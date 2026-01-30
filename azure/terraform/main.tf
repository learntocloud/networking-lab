terraform {
  required_version = ">= 1.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
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

provider "azurerm" {
  features {}
}

resource "random_id" "deployment" {
  byte_length = 4
}

resource "azurerm_resource_group" "main" {
  name     = "rg-networking-lab-${random_id.deployment.hex}"
  location = var.location

  tags = {
    project = "networking-lab"
    purpose = "learning"
  }
}

module "network" {
  source              = "./modules/network"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  deployment_id       = random_id.deployment.hex
}

module "compute" {
  source              = "./modules/compute"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  deployment_id       = random_id.deployment.hex

  vnet_id            = module.network.vnet_id
  public_subnet_id   = module.network.public_subnet_id
  private_subnet_id  = module.network.private_subnet_id
  database_subnet_id = module.network.database_subnet_id

  bastion_nsg_id  = module.network.bastion_nsg_id
  web_nsg_id      = module.network.web_nsg_id
  api_nsg_id      = module.network.api_nsg_id
  database_nsg_id = module.network.database_nsg_id
}

module "dns" {
  source              = "./modules/dns"
  resource_group_name = azurerm_resource_group.main.name
  vnet_id             = module.network.vnet_id
  deployment_id       = random_id.deployment.hex

  web_server_ip = module.compute.web_server_private_ip
  api_server_ip = module.compute.api_server_private_ip
  db_server_ip  = module.compute.db_server_private_ip
}
