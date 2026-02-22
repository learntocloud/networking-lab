# DNS Module

resource "azurerm_private_dns_zone" "internal" {
  name                = "internal.local"
  resource_group_name = var.resource_group_name

  tags = {
    project = "networking-lab"
  }
}

resource "azurerm_private_dns_zone_virtual_network_link" "main" {
  name                  = "LabVNetLink"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.internal.name
  virtual_network_id    = var.vnet_id
  registration_enabled  = false

  tags = {
    project = "networking-lab"
  }
}
