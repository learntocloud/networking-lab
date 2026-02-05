output "vpc_self_link" {
  description = "VPC self link"
  value       = google_compute_network.main.self_link
}

output "public_subnet_link" {
  description = "Public subnet self link"
  value       = google_compute_subnetwork.public.self_link
}

output "private_subnet_link" {
  description = "Private subnet self link"
  value       = google_compute_subnetwork.private.self_link
}

output "database_subnet_link" {
  description = "Database subnet self link"
  value       = google_compute_subnetwork.database.self_link
}
