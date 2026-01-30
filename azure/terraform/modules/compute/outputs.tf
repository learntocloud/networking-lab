output "bastion_public_ip" {
  description = "Public IP of bastion host"
  value       = azurerm_public_ip.bastion.ip_address
}

output "web_server_public_ip" {
  description = "Public IP of web server"
  value       = azurerm_public_ip.web.ip_address
}

output "web_server_private_ip" {
  description = "Private IP of web server"
  value       = azurerm_network_interface.web.private_ip_address
}

output "api_server_private_ip" {
  description = "Private IP of API server"
  value       = azurerm_network_interface.api.private_ip_address
}

output "db_server_private_ip" {
  description = "Private IP of database server"
  value       = azurerm_network_interface.database.private_ip_address
}

output "ssh_private_key" {
  description = "SSH private key for VM access"
  value       = tls_private_key.ssh.private_key_pem
  sensitive   = true
}
