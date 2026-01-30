# =============================================================================
# DNS MODULE
# BUG: Task 3 - DNS records are missing or misconfigured
# =============================================================================

resource "azurerm_private_dns_zone" "internal" {
  name                = "internal.local"
  resource_group_name = var.resource_group_name

  tags = {
    project = "networking-lab"
  }
}

# =============================================================================
# BUG: Task 3 - VNet link is missing!
# The Private DNS Zone needs to be linked to the VNet for resolution to work.
#
# Students need to uncomment this resource:
# =============================================================================

# resource "azurerm_private_dns_zone_virtual_network_link" "internal" {
#   name                  = "internal-vnet-link"
#   resource_group_name   = var.resource_group_name
#   private_dns_zone_name = azurerm_private_dns_zone.internal.name
#   virtual_network_id    = var.vnet_id
#   registration_enabled  = false
# }
