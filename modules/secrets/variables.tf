variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "db_username" {
  description = "Database username"
  type        = string
}

variable "recovery_window_in_days" {
  description = "Days Secrets Manager keeps the secret after destroy. 0 deletes it immediately, which suits a demo; use 7-30 in production."
  type        = number
  default     = 0

  validation {
    condition     = var.recovery_window_in_days == 0 || (var.recovery_window_in_days >= 7 && var.recovery_window_in_days <= 30)
    error_message = "Recovery window must be 0, or between 7 and 30 days."
  }
}
