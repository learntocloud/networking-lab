variable "project_id" {
  description = "GCP project ID"
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

variable "web_server_ip" {
  description = "Web server private IP"
  type        = string
}

variable "api_server_ip" {
  description = "API server private IP"
  type        = string
}

variable "db_server_ip" {
  description = "Database server private IP"
  type        = string
}
