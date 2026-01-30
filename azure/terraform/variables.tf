variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "eastus"
}

variable "admin_username" {
  description = "Admin username for VMs"
  type        = string
  default     = "labadmin"
}
