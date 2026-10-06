# Security Groups Module - Variables

variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC the security groups belong to"
  type        = string
}

variable "ssh_allowed_cidr" {
  description = "CIDR block allowed to reach the web server over SSH"
  type        = string
  default     = "0.0.0.0/0"
}
