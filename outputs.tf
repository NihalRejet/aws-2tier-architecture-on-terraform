# AWS 2-Tier Architecture - Outputs

# ---------------------------------------------------------------------------
# Networking
# ---------------------------------------------------------------------------

output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

# ---------------------------------------------------------------------------
# Web tier
# ---------------------------------------------------------------------------

output "web_server_public_ip" {
  description = "Public IP address of the web server"
  value       = module.ec2.public_ip
}

output "web_server_public_dns" {
  description = "Public DNS name of the web server"
  value       = module.ec2.public_dns
}

output "application_url" {
  description = "URL to open the application in a browser"
  value       = "http://${module.ec2.public_ip}"
}

output "health_check_url" {
  description = "URL that reports whether the app can reach the database"
  value       = "http://${module.ec2.public_ip}/health"
}

# ---------------------------------------------------------------------------
# Data tier
# ---------------------------------------------------------------------------

output "rds_endpoint" {
  description = "Endpoint of the RDS instance (reachable only from inside the VPC)"
  value       = module.rds.db_endpoint
}

output "rds_port" {
  description = "Port of the RDS instance"
  value       = module.rds.db_port
}

output "database_name" {
  description = "Name of the database"
  value       = module.rds.db_name
}

output "db_secret_arn" {
  description = "ARN of the Secrets Manager secret holding the database credentials"
  value       = module.secrets.secret_arn
}
