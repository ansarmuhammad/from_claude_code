output "cluster_name" {
  description = "Name of the EKS cluster."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint."
  value       = module.eks.cluster_endpoint
}

output "cluster_ca_certificate" {
  description = "Base64-encoded cluster CA certificate."
  value       = module.eks.cluster_ca_certificate
  sensitive   = true
}

output "oidc_provider_arn" {
  description = "ARN of the EKS OIDC provider, for IRSA role trust policies."
  value       = module.eks.oidc_provider_arn
}

output "rds_endpoint" {
  description = "PostgreSQL RDS connection endpoint (host:port)."
  value       = module.rds.endpoint
}

output "rds_db_name" {
  description = "Default database name on the RDS instance."
  value       = module.rds.db_name
}

output "rds_password_secret_arn" {
  description = "Secrets Manager ARN holding the RDS master password."
  value       = module.rds.password_secret_arn
}

output "redis_endpoint" {
  description = "Primary endpoint address for the Redis replication group."
  value       = module.elasticache.primary_endpoint
}

output "ecr_repository_urls" {
  description = "Map of service name to ECR repository URL."
  value       = module.ecr.repository_urls
}

output "vpc_id" {
  description = "VPC ID for this environment."
  value       = module.networking.vpc_id
}
