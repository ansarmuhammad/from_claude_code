output "primary_endpoint" {
  description = "Primary (writer) endpoint address for the Redis replication group."
  value       = aws_elasticache_replication_group.this.primary_endpoint_address
}

output "reader_endpoint" {
  description = "Reader endpoint address for the Redis replication group (only populated when there are read replicas)."
  value       = aws_elasticache_replication_group.this.reader_endpoint_address
}

output "port" {
  description = "Port Redis listens on."
  value       = var.port
}

output "security_group_id" {
  description = "Security group ID attached to the Redis replication group."
  value       = aws_security_group.redis.id
}
