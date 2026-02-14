output "zone_name" {
  description = "DNS zone name"
  value       = google_dns_managed_zone.internal.name
}
