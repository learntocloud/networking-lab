output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_id" {
  value = aws_subnet.public.id
}

output "private_subnet_id" {
  value = aws_subnet.private.id
}

output "database_subnet_id" {
  value = aws_subnet.database.id
}

output "bastion_sg_id" {
  value = aws_security_group.bastion.id
}

output "web_sg_id" {
  value = aws_security_group.web.id
}

output "api_sg_id" {
  value = aws_security_group.api.id
}

output "db_sg_id" {
  value = aws_security_group.database.id
}

output "public_route_table_id" {
  value = aws_route_table.public.id
}

output "private_route_table_id" {
  value = aws_route_table.private.id
}

output "database_route_table_id" {
  value = aws_route_table.database.id
}

output "nat_gateway_id" {
  value = aws_nat_gateway.main.id
}

output "internet_gateway_id" {
  value = aws_internet_gateway.main.id
}

output "database_network_acl_id" {
  value = aws_network_acl.database.id
}
