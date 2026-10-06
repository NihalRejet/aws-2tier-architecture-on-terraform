# Security Groups Module
#
# Two tiers, two groups. The database group only trusts the web group -
# it has no CIDR-based ingress at all, so the database cannot be reached
# from the internet even if the subnet routing were misconfigured.

# Web Server Security Group
resource "aws_security_group" "web" {
  name        = "${var.project_name}-web-sg"
  description = "Web tier - allows inbound HTTP and SSH"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH from the allowed CIDR"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_allowed_cidr]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-web-sg"
    Environment = var.environment
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Database Security Group
resource "aws_security_group" "db" {
  name        = "${var.project_name}-db-sg"
  description = "Data tier - allows MySQL from the web tier only"
  vpc_id      = var.vpc_id

  ingress {
    description     = "MySQL from the web tier"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web.id]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-db-sg"
    Environment = var.environment
  }

  lifecycle {
    create_before_destroy = true
  }
}
