# EC2 Module
#
# A single Ubuntu instance in the public subnet. user_data installs Docker,
# writes the Flask app and runs it in a container on port 80.
#
# The instance gets an IAM role that can read exactly one secret: the
# database credentials. The app fetches them from Secrets Manager when it
# starts, so the password never appears in user_data or in the image.

# Latest Ubuntu 22.04 LTS AMI, published by Canonical
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_region" "current" {}

# ---------------------------------------------------------------------------
# IAM: let the web server read the database secret, and nothing else
# ---------------------------------------------------------------------------

# Trust policy: only the EC2 service may assume this role
data "aws_iam_policy_document" "assume_ec2" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "web" {
  name               = "${var.project_name}-web-role"
  assume_role_policy = data.aws_iam_policy_document.assume_ec2.json

  tags = {
    Name        = "${var.project_name}-web-role"
    Environment = var.environment
  }
}

# Permission policy: one action, on one secret
data "aws_iam_policy_document" "read_db_secret" {
  statement {
    sid       = "ReadDatabaseSecret"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.db_secret_arn]
  }
}

resource "aws_iam_role_policy" "read_db_secret" {
  name   = "read-db-secret"
  role   = aws_iam_role.web.name
  policy = data.aws_iam_policy_document.read_db_secret.json
}

# An instance profile is the container that attaches a role to an EC2 instance
resource "aws_iam_instance_profile" "web" {
  name = "${var.project_name}-web-profile"
  role = aws_iam_role.web.name

  tags = {
    Name        = "${var.project_name}-web-profile"
    Environment = var.environment
  }
}

# ---------------------------------------------------------------------------
# Web server
# ---------------------------------------------------------------------------

resource "aws_instance" "web" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = var.public_subnet_id
  vpc_security_group_ids      = [var.web_security_group_id]
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.web.name

  # No secrets in here: only where the database is and which secret to read
  user_data = templatefile("${path.module}/templates/user_data.sh", {
    db_host       = var.db_host
    db_name       = var.db_name
    db_secret_arn = var.db_secret_arn
    aws_region    = data.aws_region.current.name
  })

  # user_data only runs on first boot, so a changed script would otherwise
  # never take effect. Replace the instance instead.
  user_data_replace_on_change = true

  # Require IMDSv2, so instance metadata cannot be read through a simple
  # server-side request forgery against the application.
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
    # 2, not 1: the app runs inside a Docker container, which is one extra
    # network hop from the host. With 1, the IMDSv2 token reply never reaches
    # the container and the app cannot get the role's credentials.
    http_put_response_hop_limit = 2
  }

  root_block_device {
    encrypted   = true
    volume_type = "gp3"
    volume_size = var.root_volume_size
  }

  tags = {
    Name        = "${var.project_name}-web-server"
    Environment = var.environment
  }
}
