output "dns_zone_name" {
  description = "Private DNS zone name"
  value       = aws_route53_zone.internal.name
}

output "dns_zone_id" {
  description = "Private DNS zone ID"
  value       = aws_route53_zone.internal.zone_id
}
