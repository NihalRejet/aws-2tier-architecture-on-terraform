# Secrets Module
#
# Generates the database master password and stores it in Secrets Manager.
# The random suffix on the secret name matters: Secrets Manager keeps deleted
# secrets for a recovery window, and a re-apply would otherwise collide with
# the name of a secret that is still scheduled for deletion.

resource "random_password" "db_password" {
  length  = 16
  special = true
  # RDS rejects '/', '@', '"' and spaces in master passwords
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "random_id" "suffix" {
  byte_length = 4
}

resource "aws_secretsmanager_secret" "db_password" {
  name        = "${var.project_name}-${var.environment}-db-password-${random_id.suffix.hex}"
  description = "Database credentials for ${var.project_name}"

  # 0 deletes immediately on destroy. Demo setting - in production use 7-30
  # days so a mistaken delete can be recovered.
  recovery_window_in_days = var.recovery_window_in_days

  tags = {
    Name        = "${var.project_name}-db-password"
    Environment = var.environment
  }
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id = aws_secretsmanager_secret.db_password.id
  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db_password.result
    engine   = "mysql"
  })
}
