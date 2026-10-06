# RDS Module
#
# A MySQL instance placed in the private subnets with no public route.
# The subnet group spans two AZs because RDS requires it, but the instance
# itself is single-AZ (multi_az is off to stay inside the free tier).

# DB Subnet Group
resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = {
    Name        = "${var.project_name}-db-subnet-group"
    Environment = var.environment
  }
}

# RDS MySQL Instance
resource "aws_db_instance" "main" {
  identifier     = "${var.project_name}-db"
  engine         = "mysql"
  engine_version = var.engine_version
  instance_class = var.instance_class

  # General Purpose SSD on MySQL has a 20 GiB minimum - values below that
  # are rejected by the RDS API.
  allocated_storage = var.allocated_storage
  storage_type      = "gp2"
  storage_encrypted = true

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  parameter_group_name   = "default.mysql8.0"
  vpc_security_group_ids = [var.db_security_group_id]
  db_subnet_group_name   = aws_db_subnet_group.main.name
  publicly_accessible    = false

  backup_retention_period    = var.backup_retention_period
  copy_tags_to_snapshot      = true
  auto_minor_version_upgrade = true

  # Demo environment: allow a clean `terraform destroy` without leaving
  # a final snapshot behind. Do not do this in production.
  skip_final_snapshot = true
  deletion_protection = false

  tags = {
    Name        = "${var.project_name}-rds"
    Environment = var.environment
  }
}
