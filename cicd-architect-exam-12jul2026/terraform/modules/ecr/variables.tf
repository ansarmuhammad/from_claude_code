variable "name_prefix" {
  description = "Prefix used to name all ECR repositories (e.g. cicd-exam-dev)."
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, production). Used for tagging."
  type        = string
}

variable "repository_names" {
  description = "Names of the services to create ECR repositories for."
  type        = list(string)
  default     = ["api-service", "web-frontend", "worker-service"]
}

variable "image_tag_mutability" {
  description = "Whether image tags can be overwritten (MUTABLE) or not (IMMUTABLE). IMMUTABLE is recommended for staging/production."
  type        = string
  default     = "MUTABLE"
}

variable "scan_on_push" {
  description = "Whether to enable image vulnerability scanning on push."
  type        = bool
  default     = true
}

variable "untagged_image_expiry_days" {
  description = "Number of days after which untagged images are expired by the lifecycle policy."
  type        = number
  default     = 14
}

variable "tagged_image_count_limit" {
  description = "Maximum number of tagged images to retain per repository before the oldest are expired."
  type        = number
  default     = 30
}

variable "tags" {
  description = "Additional tags to apply to all ECR resources."
  type        = map(string)
  default     = {}
}
