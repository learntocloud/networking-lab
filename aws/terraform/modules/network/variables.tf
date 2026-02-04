variable "deployment_id" {
  description = "Deployment identifier"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR"
  type        = string
}

variable "public_subnet_cidr" {
  description = "Public subnet CIDR"
  type        = string
}

variable "private_subnet_cidr" {
  description = "Private subnet CIDR"
  type        = string
}

variable "database_subnet_cidr" {
  description = "Database subnet CIDR"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}
