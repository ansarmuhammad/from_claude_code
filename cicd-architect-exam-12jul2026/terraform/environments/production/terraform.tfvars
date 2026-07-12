aws_region  = "us-east-1"
name_prefix = "cicd-exam-prod"
environment = "production"

vpc_cidr             = "10.2.0.0/16"
azs                  = ["us-east-1a", "us-east-1b", "us-east-1c"]
public_subnet_cidrs  = ["10.2.0.0/24", "10.2.1.0/24", "10.2.2.0/24"]
private_subnet_cidrs = ["10.2.10.0/24", "10.2.11.0/24", "10.2.12.0/24"]

eks_cluster_version     = "1.29"
eks_node_instance_types = ["m5.xlarge"]
eks_node_desired_size   = 4
eks_node_min_size       = 3
eks_node_max_size       = 8

rds_instance_class    = "db.r6g.large"
rds_allocated_storage = 100
rds_engine_version    = "15.5"
rds_db_name           = "appdb"
rds_username          = "appuser"

redis_node_type      = "cache.r6g.large"
redis_engine_version = "7.1"

ecr_repository_names = ["api-service", "web-frontend", "worker-service"]
