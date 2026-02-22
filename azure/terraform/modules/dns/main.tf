# DNS Module

resource "azurerm_private_dns_zone" "internal" {
  name                = "internal.local"
  resource_group_name = var.resource_group_name

  tags = {
    project = "networking-lab"
  }
}
