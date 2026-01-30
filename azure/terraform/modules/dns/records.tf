# =============================================================================
# DNS RECORDS
# BUG: Task 3 - DNS records are missing!
#
# Students need to add A records for:
# - web.internal.local -> web server private IP
# - api.internal.local -> API server private IP
# - db.internal.local  -> database server private IP
#
# Uncomment the resources below to fix Task 3:
# =============================================================================

# resource "azurerm_private_dns_a_record" "web" {
#   name                = "web"
#   zone_name           = azurerm_private_dns_zone.internal.name
#   resource_group_name = var.resource_group_name
#   ttl                 = 300
#   records             = [var.web_server_ip]
# }

# resource "azurerm_private_dns_a_record" "api" {
#   name                = "api"
#   zone_name           = azurerm_private_dns_zone.internal.name
#   resource_group_name = var.resource_group_name
#   ttl                 = 300
#   records             = [var.api_server_ip]
# }

# resource "azurerm_private_dns_a_record" "db" {
#   name                = "db"
#   zone_name           = azurerm_private_dns_zone.internal.name
#   resource_group_name = var.resource_group_name
#   ttl                 = 300
#   records             = [var.db_server_ip]
# }
