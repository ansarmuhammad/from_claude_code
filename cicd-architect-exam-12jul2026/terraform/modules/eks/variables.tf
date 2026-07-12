variable "name_prefix" {
  description = "Prefix used to name the EKS cluster and its associated resources (e.g. cicd-exam-dev)."
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, production). Used for tagging."
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS control plane."
  type        = string
  default     = "1.29"
}

variable "vpc_id" {
  description = "VPC ID in which to create the cluster and node groups."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for worker nodes (and the control plane ENIs)."
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "Public subnet IDs. Included in cluster subnet list to allow public-facing load balancers; the control plane endpoint access itself is controlled separately."
  type        = list(string)
}

variable "endpoint_private_access" {
  description = "Whether the EKS private API server endpoint is enabled."
  type        = bool
  default     = true
}

variable "endpoint_public_access" {
  description = "Whether the EKS public API server endpoint is enabled. Recommended false (or CIDR-restricted) in production."
  type        = bool
  default     = true
}

variable "public_access_cidrs" {
  description = "CIDR blocks allowed to access the public EKS endpoint, when enabled."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# --- Managed node group sizing ---

variable "node_instance_types" {
  description = "EC2 instance types for the managed node group, e.g. [\"t3.medium\"] for dev, [\"m5.large\"] for production."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_capacity_type" {
  description = "Capacity type for the managed node group: ON_DEMAND or SPOT."
  type        = string
  default     = "ON_DEMAND"
}

variable "node_desired_size" {
  description = "Desired number of worker nodes."
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimum number of worker nodes."
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Maximum number of worker nodes."
  type        = number
  default     = 3
}

variable "node_disk_size" {
  description = "Root EBS volume size (GiB) for worker nodes."
  type        = number
  default     = 50
}

variable "tags" {
  description = "Additional tags to apply to all EKS resources."
  type        = map(string)
  default     = {}
}
