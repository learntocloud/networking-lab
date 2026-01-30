output "deployment_id" {
  description = "Unique deployment identifier"
  value       = random_id.deployment.hex
}

output "resource_group_name" {
  description = "Resource group name"
  value       = azurerm_resource_group.main.name
}

output "bastion_public_ip" {
  description = "Public IP of the bastion host"
  value       = module.compute.bastion_public_ip
}

output "web_server_public_ip" {
  description = "Public IP of the web server (for HTTP/HTTPS testing)"
  value       = module.compute.web_server_public_ip
}

output "web_server_private_ip" {
  description = "Private IP of the web server"
  value       = module.compute.web_server_private_ip
}

output "api_server_private_ip" {
  description = "Private IP of the API server"
  value       = module.compute.api_server_private_ip
}

output "database_server_private_ip" {
  description = "Private IP of the database server"
  value       = module.compute.db_server_private_ip
}

output "ssh_private_key" {
  description = "SSH private key for VM access"
  value       = module.compute.ssh_private_key
  sensitive   = true
}

output "connection_instructions" {
  description = "How to connect to the lab"
  value       = <<-EOT

    ============================================
    NETWORKING LAB - CONNECTION INFO
    ============================================

    1. Save the SSH key:
       terraform output -raw ssh_private_key > ~/.ssh/netlab-key
       chmod 600 ~/.ssh/netlab-key

    2. Connect to bastion:
       ssh -i ~/.ssh/netlab-key ${var.admin_username}@${module.compute.bastion_public_ip}

    3. From bastion, connect to internal hosts:
       ssh ${var.admin_username}@${module.compute.web_server_private_ip}   # web server
       ssh ${var.admin_username}@${module.compute.api_server_private_ip}   # api server
       ssh ${var.admin_username}@${module.compute.db_server_private_ip}    # database server

    4. Test web endpoint:
       curl -I http://${module.compute.web_server_public_ip}

    Resource Group: ${azurerm_resource_group.main.name}
    ============================================
  EOT
}
