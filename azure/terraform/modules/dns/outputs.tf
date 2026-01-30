output "dns_zone_name" {
  description = "Private DNS zone name"
  value       = azurerm_private_dns_zone.internal.name
}

output "dns_zone_id" {
  description = "Private DNS zone ID"
  value       = azurerm_private_dns_zone.internal.id
}
