output "endpoint" {
  description = "Connection endpoint (host:port) of the RDS instance."
  value       = aws_db_instance.this.endpoint
}

output "address" {
  description = "Hostname of the RDS instance (without port)."
  value       = aws_db_instance.this.address
}

output "port" {
  description = "Port the RDS instance listens on."
  value       = aws_db_instance.this.port
}

output "db_name" {
  description = "Name of the default database on the instance."
  value       = aws_db_instance.this.db_name
}

output "username" {
  description = "Master username for the database (not the password)."
  value       = aws_db_instance.this.username
}

output "security_group_id" {
  description = "Security group ID attached to the RDS instance."
  value       = aws_security_group.rds.id
}

output "password_secret_arn" {
  description = "ARN of the Secrets Manager secret holding the master password. Fetch the password at deploy/runtime via this secret - it is intentionally not exposed as a plaintext Terraform output."
  value       = aws_secretsmanager_secret.db_password.arn
}
