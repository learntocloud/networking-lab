# =============================================================================
# ROUTES CONFIGURATION
# BUG: Task 2 - Missing NAT Gateway association for private subnet
#
# The private subnet needs outbound internet access via NAT Gateway.
# Currently, there's no association between the NAT Gateway and the private subnet.
#
# Students need to add:
#   resource "azurerm_subnet_nat_gateway_association" "private" {
#     subnet_id      = azurerm_subnet.private.id
#     nat_gateway_id = azurerm_nat_gateway.main.id
#   }
#
# Uncomment the resource below to fix Task 2:
# =============================================================================

# resource "azurerm_subnet_nat_gateway_association" "private" {
#   subnet_id      = azurerm_subnet.private.id
#   nat_gateway_id = azurerm_nat_gateway.main.id
# }

# Custom route for database subnet to block direct internet access
resource "azurerm_route" "database_no_internet" {
  name                = "block-internet"
  resource_group_name = var.resource_group_name
  route_table_name    = azurerm_route_table.database.name
  address_prefix      = "0.0.0.0/0"
  next_hop_type       = "None"
}
