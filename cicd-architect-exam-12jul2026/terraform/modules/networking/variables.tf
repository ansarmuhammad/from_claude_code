variable "name_prefix" {
  description = "Prefix used to name all networking resources (e.g. cicd-exam-dev)."
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, production). Used for tagging."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "List of availability zones to spread subnets across. Provide 1 for dev, 2-3 for staging/production."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets, one per AZ, in the same order as var.azs."
  type        = list(string)
  default     = ["10.0.0.0/24", "10.0.1.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets, one per AZ, in the same order as var.azs."
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "single_nat_gateway" {
  description = "If true, provision a single shared NAT Gateway for all private subnets (cheaper, used for dev). If false, one NAT Gateway per AZ for HA (used for staging/production)."
  type        = bool
  default     = true
}

variable "enable_dns_hostnames" {
  description = "Enable DNS hostnames in the VPC."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags to apply to all networking resources."
  type        = map(string)
  default     = {}
}
