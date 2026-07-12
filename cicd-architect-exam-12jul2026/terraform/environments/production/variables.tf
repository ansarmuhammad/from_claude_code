variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Prefix used to name all resources in this environment."
  type        = string
  default     = "cicd-exam-prod"
}

variable "environment" {
  description = "Environment name."
  type        = string
  default     = "production"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.2.0.0/16"
}

variable "azs" {
  description = "Availability zones to spread subnets across. Production uses 3 AZs for full HA."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.2.0.0/24", "10.2.1.0/24", "10.2.2.0/24"]
}

variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.2.10.0/24", "10.2.11.0/24", "10.2.12.0/24"]
}

variable "eks_cluster_version" {
  type    = string
  default = "1.29"
}

variable "eks_node_instance_types" {
  type    = list(string)
  default = ["m5.xlarge"]
}

variable "eks_node_desired_size" {
  type    = number
  default = 4
}

variable "eks_node_min_size" {
  type    = number
  default = 3
}

variable "eks_node_max_size" {
  type    = number
  default = 8
}

variable "rds_instance_class" {
  type    = string
  default = "db.r6g.large"
}

variable "rds_allocated_storage" {
  type    = number
  default = 100
}

variable "rds_engine_version" {
  type    = string
  default = "15.5"
}

variable "rds_db_name" {
  type    = string
  default = "appdb"
}

variable "rds_username" {
  type    = string
  default = "appuser"
}

variable "redis_node_type" {
  type    = string
  default = "cache.r6g.large"
}

variable "redis_engine_version" {
  type    = string
  default = "7.1"
}

variable "ecr_repository_names" {
  type    = list(string)
  default = ["api-service", "web-frontend", "worker-service"]
}
