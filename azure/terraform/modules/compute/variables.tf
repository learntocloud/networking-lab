variable "resource_group_name" {
  description = "Resource group name"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "deployment_id" {
  description = "Unique deployment identifier"
  type        = string
}

variable "admin_username" {
  description = "Admin username for VMs"
  type        = string
  default     = "labadmin"
}

variable "vnet_id" {
  description = "Virtual Network ID"
  type        = string
}

variable "public_subnet_id" {
  description = "Public subnet ID"
  type        = string
}

variable "private_subnet_id" {
  description = "Private subnet ID"
  type        = string
}

variable "database_subnet_id" {
  description = "Database subnet ID"
  type        = string
}

variable "bastion_nsg_id" {
  description = "Bastion NSG ID"
  type        = string
}

variable "web_nsg_id" {
  description = "Web server NSG ID"
  type        = string
}

variable "api_nsg_id" {
  description = "API server NSG ID"
  type        = string
}

variable "database_nsg_id" {
  description = "Database NSG ID"
  type        = string
}
