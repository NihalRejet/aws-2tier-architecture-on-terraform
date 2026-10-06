# AWS 2-Tier Architecture - Input Variables

# ---------------------------------------------------------------------------
# General
# ---------------------------------------------------------------------------

variable "project_name" {
  description = "Name of the project - used as a prefix when naming and tagging resources"
  type        = string
  default     = "aws-2tier-rds-demo"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "aws_region" {
  description = "AWS region to deploy resources into"
  type        = string
  default     = "us-east-1"
}

# ---------------------------------------------------------------------------
# Networking
# ---------------------------------------------------------------------------

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet that hosts the web tier"
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for the private subnets. RDS requires two, in different AZs."
  type        = list(string)
  default     = ["10.0.2.0/24", "10.0.3.0/24"]

  validation {
    condition     = length(var.private_subnet_cidrs) == 2
    error_message = "Exactly two private subnet CIDRs are required for the RDS subnet group."
  }
}

variable "ssh_allowed_cidr" {
  description = "CIDR block allowed to reach the web server over SSH. Set this to your own IP (e.g. 203.0.113.4/32) - leaving it open to the world is unsafe."
  type        = string
  default     = "0.0.0.0/0"
}

# ---------------------------------------------------------------------------
# Compute
# ---------------------------------------------------------------------------

variable "ec2_instance_type" {
  description = "EC2 instance type for the web server"
  type        = string
  default     = "t3.micro"
}

# ---------------------------------------------------------------------------
# Database
# ---------------------------------------------------------------------------

variable "db_name" {
  description = "Name of the initial database created on the RDS instance"
  type        = string
  default     = "webappdb"
}

variable "db_username" {
  description = "Database master username"
  type        = string
  default     = "admin"
  sensitive   = true
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "db_allocated_storage" {
  description = "Allocated storage for RDS, in GB. General Purpose SSD on MySQL has a 20 GB minimum, which is also the free-tier allowance."
  type        = number
  default     = 20

  validation {
    condition     = var.db_allocated_storage >= 20
    error_message = "General Purpose SSD on RDS MySQL requires at least 20 GB."
  }
}

variable "db_engine_version" {
  description = "MySQL engine version"
  type        = string
  default     = "8.0"
}

variable "db_backup_retention_period" {
  description = "Number of days to retain automated RDS backups. 0 disables backups."
  type        = number
  default     = 7
}
