output "region" {
  description = "AWS region where resources are deployed"
  value       = var.aws_region
}

output "deployment_id" {
  description = "Unique deployment identifier"
  value       = random_id.deployment.hex
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.network.vpc_id
}

output "public_subnet_id" {
  description = "Public subnet ID (bastion, web, NAT gateway)"
  value       = module.network.public_subnet_id
}

output "private_subnet_id" {
  description = "Private subnet ID (API)"
  value       = module.network.private_subnet_id
}

output "database_subnet_id" {
  description = "Database subnet ID"
  value       = module.network.database_subnet_id
}

output "private_route_table_id" {
  description = "Route table associated with the private subnet"
  value       = module.network.private_route_table_id
}

output "nat_gateway_id" {
  description = "NAT gateway in the public subnet"
  value       = module.network.nat_gateway_id
}

output "database_network_acl_id" {
  description = "Network ACL associated with the database subnet"
  value       = module.network.database_network_acl_id
}

output "dns_zone_id" {
  description = "Private DNS zone ID for this lab"
  value       = module.dns.dns_zone_id
}

output "bastion_public_ip" {
  description = "Public IP of the bastion host"
  value       = module.compute.bastion_public_ip
}

output "bastion_private_ip" {
  description = "Private IP of the bastion host"
  value       = module.compute.bastion_private_ip
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

output "bastion_instance_id" {
  description = "Bastion EC2 instance ID"
  value       = module.compute.bastion_instance_id
}

output "web_instance_id" {
  description = "Web EC2 instance ID"
  value       = module.compute.web_instance_id
}

output "api_instance_id" {
  description = "API EC2 instance ID"
  value       = module.compute.api_instance_id
}

output "database_instance_id" {
  description = "Database EC2 instance ID"
  value       = module.compute.db_instance_id
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

    Region:         ${var.aws_region}
    Deployment ID:  ${random_id.deployment.hex}
    VPC:            ${module.network.vpc_id}

    1. Save the SSH key (setup.sh already did this):
       cd aws/terraform
       terraform output -raw ssh_private_key > ~/.ssh/netlab-key
       chmod 600 ~/.ssh/netlab-key

    2. Connect to the bastion:
       ssh -i ~/.ssh/netlab-key ${var.admin_username}@${module.compute.bastion_public_ip}

    3. From the bastion, connect to internal hosts:
       ssh ${module.compute.web_private_ip}   # web server (public subnet)
       ssh ${module.compute.api_private_ip}   # API server (private subnet)
       ssh ${module.compute.db_private_ip}    # database server (database subnet)

    4. Test the public web endpoint from your machine:
       curl -I http://${module.compute.web_public_ip}

    Useful IDs for the AWS CLI:
       Private route table:  ${module.network.private_route_table_id}
       NAT gateway:          ${module.network.nat_gateway_id}
       Database network ACL: ${module.network.database_network_acl_id}
       Route 53 zone:        ${module.dns.dns_zone_id}
       Security groups:      bastion ${module.network.bastion_sg_id}
                             web     ${module.network.web_sg_id}
                             api     ${module.network.api_sg_id}
                             db      ${module.network.db_sg_id}

    ============================================
  EOT
}
