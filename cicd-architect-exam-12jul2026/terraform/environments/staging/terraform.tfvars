aws_region  = "us-east-1"
name_prefix = "cicd-exam-staging"
environment = "staging"

vpc_cidr             = "10.1.0.0/16"
azs                  = ["us-east-1a", "us-east-1b"]
public_subnet_cidrs  = ["10.1.0.0/24", "10.1.1.0/24"]
private_subnet_cidrs = ["10.1.10.0/24", "10.1.11.0/24"]

eks_cluster_version     = "1.29"
eks_node_instance_types = ["m5.large"]
eks_node_desired_size   = 3
eks_node_min_size       = 2
eks_node_max_size       = 5

rds_instance_class    = "db.t3.medium"
rds_allocated_storage = 50
rds_engine_version    = "15.5"
rds_db_name           = "appdb"
rds_username          = "appuser"

redis_node_type      = "cache.t3.small"
redis_engine_version = "7.1"

ecr_repository_names = ["api-service", "web-frontend", "worker-service"]
