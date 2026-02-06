variable "deployment_id" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "admin_username" {
  type = string
}

variable "public_subnet_id" {
  type = string
}

variable "private_subnet_id" {
  type = string
}

variable "database_subnet_id" {
  type = string
}

variable "bastion_sg_id" {
  type = string
}

variable "web_sg_id" {
  type = string
}

variable "api_sg_id" {
  type = string
}

variable "db_sg_id" {
  type = string
}

variable "vpc_id" {
  type = string
}
