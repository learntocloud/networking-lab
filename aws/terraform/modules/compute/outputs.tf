output "bastion_public_ip" {
  value = aws_eip.bastion.public_ip
}

output "bastion_private_ip" {
  value = aws_instance.bastion.private_ip
}

output "web_public_ip" {
  value = aws_eip.web.public_ip
}

output "web_private_ip" {
  value = aws_instance.web.private_ip
}

output "api_private_ip" {
  value = aws_instance.api.private_ip
}

output "db_private_ip" {
  value = aws_instance.database.private_ip
}

output "ssh_private_key" {
  value     = tls_private_key.ssh.private_key_pem
  sensitive = true
}
