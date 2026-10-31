output "db_password" {
  description = "Generated database password"
  value       = random_password.db_password.result
  sensitive   = true
}

output "secret_arn" {
  description = "ARN of the secret in Secrets Manager"
  # Taken from the secret *version*, not the secret, so anything that uses
  # this ARN waits until the username and password are actually stored.
  value = aws_secretsmanager_secret_version.db_password.arn
}
