variable "name_prefix" {
  description = "Prefix used to name all ElastiCache resources (e.g. cicd-exam-dev)."
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, production). Used for tagging."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID in which to create the subnet group and security group."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs to use for the ElastiCache subnet group."
  type        = list(string)
}

variable "eks_node_security_group_id" {
  description = "Security group ID of the EKS worker nodes/pods; granted ingress to Redis on its port."
  type        = string
}

variable "engine_version" {
  description = "Redis engine version."
  type        = string
  default     = "7.1"
}

variable "node_type" {
  description = "ElastiCache node instance type, e.g. cache.t3.micro for dev, cache.r6g.large for production."
  type        = string
  default     = "cache.t3.micro"
}

variable "port" {
  description = "Port Redis listens on."
  type        = number
  default     = 6379
}

variable "multi_az_enabled" {
  description = "Whether to enable Multi-AZ with automatic failover. Requires at least 2 cache nodes/replicas; use for staging/production."
  type        = bool
  default     = false
}

variable "num_cache_clusters" {
  description = "Number of cache clusters (primary + replicas) in the replication group. Use 1 for dev (single node, no HA), 2+ for staging/production."
  type        = number
  default     = 1
}

variable "at_rest_encryption_enabled" {
  description = "Whether to encrypt data at rest."
  type        = bool
  default     = true
}

variable "transit_encryption_enabled" {
  description = "Whether to encrypt data in transit (requires Redis AUTH / TLS-aware client)."
  type        = bool
  default     = false
}

variable "snapshot_retention_limit" {
  description = "Number of days to retain automatic snapshots. 0 disables snapshots (fine for dev)."
  type        = number
  default     = 0
}

variable "tags" {
  description = "Additional tags to apply to all ElastiCache resources."
  type        = map(string)
  default     = {}
}
