variable "deployment_id" {
  description = "Unique deployment identifier"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "web_server_ip" {
  description = "Private IP of web server"
  type        = string
}

variable "api_server_ip" {
  description = "Private IP of API server"
  type        = string
}

variable "db_server_ip" {
  description = "Private IP of database server"
  type        = string
}
