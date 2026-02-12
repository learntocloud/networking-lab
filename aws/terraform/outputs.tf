output "deployment_id" {
  description = "Unique deployment identifier"
  value       = random_id.deployment.hex
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.network.vpc_id
}

output "bastion_public_ip" {
  description = "Public IP of the bastion host"
  value       = module.compute.bastion_public_ip
}

output "web_server_public_ip" {
  description = "Public IP of the web server"
  value       = module.compute.web_public_ip
}

output "web_server_private_ip" {
  description = "Private IP of the web server"
  value       = module.compute.web_private_ip
}

output "api_server_private_ip" {
  description = "Private IP of the API server"
  value       = module.compute.api_private_ip
}

output "database_server_private_ip" {
  description = "Private IP of the database server"
  value       = module.compute.db_private_ip
}

output "ssh_private_key" {
  description = "SSH private key for VM access"
  value       = module.compute.ssh_private_key
  sensitive   = true
}

output "admin_username" {
  description = "Admin username"
  value       = var.admin_username
}

output "bastion_sg_id" {
  description = "Bastion security group ID"
  value       = module.network.bastion_sg_id
}

output "web_sg_id" {
  description = "Web security group ID"
  value       = module.network.web_sg_id
}

output "api_sg_id" {
  description = "API security group ID"
  value       = module.network.api_sg_id
}

output "db_sg_id" {
  description = "Database security group ID"
  value       = module.network.db_sg_id
}

output "connection_instructions" {
  description = "How to connect to the lab"
  value       = <<-EOT

    ============================================
    NETWORKING LAB - CONNECTION INFO (AWS)
    ============================================

    1. Save the SSH key (run from aws/terraform directory):
       cd aws/terraform
       terraform output -raw ssh_private_key > ~/.ssh/netlab-key
       chmod 600 ~/.ssh/netlab-key

    2. Connect to bastion:
       ssh -i ~/.ssh/netlab-key ${var.admin_username}@${module.compute.bastion_public_ip}

    3. From bastion, connect to internal hosts:
       ssh ${var.admin_username}@${module.compute.web_private_ip}   # web server
       ssh ${var.admin_username}@${module.compute.api_private_ip}   # api server
       ssh ${var.admin_username}@${module.compute.db_private_ip}    # database server

    4. Test web endpoint:
       curl -I http://${module.compute.web_public_ip}

    ============================================
  EOT
}
