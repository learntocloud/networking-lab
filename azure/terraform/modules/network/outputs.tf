output "vnet_id" {
  description = "Virtual Network ID"
  value       = azurerm_virtual_network.main.id
}

output "vnet_name" {
  description = "Virtual Network name"
  value       = azurerm_virtual_network.main.name
}

output "public_subnet_id" {
  description = "Public subnet ID"
  value       = azurerm_subnet.public.id
}

output "private_subnet_id" {
  description = "Private subnet ID"
  value       = azurerm_subnet.private.id
}

output "database_subnet_id" {
  description = "Database subnet ID"
  value       = azurerm_subnet.database.id
}

output "nat_gateway_id" {
  description = "NAT Gateway ID"
  value       = azurerm_nat_gateway.main.id
}

output "bastion_nsg_id" {
  description = "Bastion NSG ID"
  value       = azurerm_network_security_group.bastion.id
}

output "web_nsg_id" {
  description = "Web server NSG ID"
  value       = azurerm_network_security_group.web.id
}

output "api_nsg_id" {
  description = "API server NSG ID"
  value       = azurerm_network_security_group.api.id
}

output "database_nsg_id" {
  description = "Database NSG ID"
  value       = azurerm_network_security_group.database.id
}
