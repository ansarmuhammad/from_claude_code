variable "name_prefix" {
  description = "Prefix used to name all RDS resources (e.g. cicd-exam-dev)."
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, production). Used for tagging."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID in which to create the DB subnet group and security group."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs to use for the DB subnet group."
  type        = list(string)
}

variable "eks_node_security_group_id" {
  description = "Security group ID of the EKS worker nodes/pods; granted ingress to the database on the Postgres port."
  type        = string
}

variable "engine_version" {
  description = "PostgreSQL engine version."
  type        = string
  default     = "15.5"
}

variable "instance_class" {
  description = "RDS instance class, e.g. db.t3.micro for dev, db.r6g.large for production."
  type        = string
  default     = "db.t3.micro"
}

variable "allocated_storage" {
  description = "Allocated storage in GiB."
  type        = number
  default     = 20
}

variable "max_allocated_storage" {
  description = "Upper limit (GiB) for RDS storage autoscaling. Set equal to allocated_storage to disable."
  type        = number
  default     = 100
}

variable "db_name" {
  description = "Name of the default database created on the instance."
  type        = string
  default     = "appdb"
}

variable "username" {
  description = "Master username for the database."
  type        = string
  default     = "appuser"
}

variable "port" {
  description = "Port the database listens on."
  type        = number
  default     = 5432
}

variable "multi_az" {
  description = "Whether to deploy a Multi-AZ standby replica. True for staging/production."
  type        = bool
  default     = false
}

variable "backup_retention_period" {
  description = "Number of days to retain automated backups."
  type        = number
  default     = 7
}

variable "deletion_protection" {
  description = "Whether to enable deletion protection. Should be true for production."
  type        = bool
  default     = false
}

variable "skip_final_snapshot" {
  description = "Whether to skip the final snapshot on destroy. Should be false for production."
  type        = bool
  default     = true
}

variable "storage_encrypted" {
  description = "Whether to encrypt storage at rest."
  type        = bool
  default     = true
}

variable "family" {
  description = "DB parameter group family, must match the engine major version (e.g. postgres15)."
  type        = string
  default     = "postgres15"
}

variable "performance_insights_enabled" {
  description = "Whether to enable Performance Insights."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags to apply to all RDS resources."
  type        = map(string)
  default     = {}
}
