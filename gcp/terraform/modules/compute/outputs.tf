output "bastion_public_ip" {
  description = "Bastion public IP"
  value       = google_compute_instance.bastion.network_interface[0].access_config[0].nat_ip
}

output "web_server_public_ip" {
  description = "Web server public IP"
  value       = google_compute_instance.web.network_interface[0].access_config[0].nat_ip
}

output "web_server_private_ip" {
  description = "Web server private IP"
  value       = google_compute_instance.web.network_interface[0].network_ip
}

output "api_server_private_ip" {
  description = "API server private IP"
  value       = google_compute_instance.api.network_interface[0].network_ip
}

output "db_server_private_ip" {
  description = "Database server private IP"
  value       = google_compute_instance.database.network_interface[0].network_ip
}

output "ssh_private_key" {
  description = "SSH private key for VM access"
  value       = tls_private_key.ssh.private_key_pem
  sensitive   = true
}
