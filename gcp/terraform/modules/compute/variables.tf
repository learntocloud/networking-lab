variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
}

variable "zone" {
  description = "GCP zone"
  type        = string
}

variable "deployment_id" {
  description = "Deployment identifier"
  type        = string
}

variable "vpc_self_link" {
  description = "VPC self link"
  type        = string
}

variable "public_subnet_link" {
  description = "Public subnet self link"
  type        = string
}

variable "private_subnet_link" {
  description = "Private subnet self link"
  type        = string
}

variable "database_subnet_link" {
  description = "Database subnet self link"
  type        = string
}

variable "admin_username" {
  description = "Admin username for VMs"
  type        = string
  default     = "labadmin"
}
