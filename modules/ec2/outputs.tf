# EC2 Module - Outputs

output "instance_id" {
  description = "ID of the EC2 instance"
  value       = aws_instance.web.id
}

output "public_ip" {
  description = "Public IP of the EC2 instance"
  value       = aws_instance.web.public_ip
}

output "public_dns" {
  description = "Public DNS of the EC2 instance"
  value       = aws_instance.web.public_dns
}

output "iam_role_name" {
  description = "Name of the IAM role attached to the web server"
  value       = aws_iam_role.web.name
}
