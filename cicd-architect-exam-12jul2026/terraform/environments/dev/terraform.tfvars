aws_region  = "us-east-1"
name_prefix = "cicd-exam-dev"
environment = "dev"

vpc_cidr             = "10.0.0.0/16"
azs                  = ["us-east-1a", "us-east-1b"]
public_subnet_cidrs  = ["10.0.0.0/24", "10.0.1.0/24"]
private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]

eks_cluster_version     = "1.29"
eks_node_instance_types = ["t3.medium"]
eks_node_desired_size   = 2
eks_node_min_size       = 1
eks_node_max_size       = 3

rds_instance_class    = "db.t3.micro"
rds_allocated_storage = 20
rds_engine_version    = "15.5"
rds_db_name           = "appdb"
rds_username          = "appuser"

redis_node_type      = "cache.t3.micro"
redis_engine_version = "7.1"

ecr_repository_names = ["api-service", "web-frontend", "worker-service"]
