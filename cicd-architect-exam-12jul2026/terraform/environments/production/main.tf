module "networking" {
  source = "../../modules/networking"

  name_prefix          = var.name_prefix
  environment          = var.environment
  vpc_cidr             = var.vpc_cidr
  azs                  = var.azs
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs

  # Production is fully HA: one NAT Gateway per AZ.
  single_nat_gateway = false
}

module "eks" {
  source = "../../modules/eks"

  name_prefix        = var.name_prefix
  environment        = var.environment
  cluster_version    = var.eks_cluster_version
  vpc_id             = module.networking.vpc_id
  private_subnet_ids = module.networking.private_subnet_ids
  public_subnet_ids  = module.networking.public_subnet_ids

  node_instance_types = var.eks_node_instance_types
  node_capacity_type  = "ON_DEMAND"
  node_desired_size   = var.eks_node_desired_size
  node_min_size       = var.eks_node_min_size
  node_max_size       = var.eks_node_max_size
  node_disk_size      = 100

  # Production locks the public endpoint down; in a real deployment this
  # would be a specific corporate/VPN CIDR list, not 0.0.0.0/0.
  endpoint_public_access  = true
  endpoint_private_access = true
}

module "rds" {
  source = "../../modules/rds"

  name_prefix                = var.name_prefix
  environment                = var.environment
  vpc_id                     = module.networking.vpc_id
  private_subnet_ids         = module.networking.private_subnet_ids
  eks_node_security_group_id = module.eks.node_security_group_id

  engine_version    = var.rds_engine_version
  instance_class    = var.rds_instance_class
  allocated_storage = var.rds_allocated_storage
  db_name           = var.rds_db_name
  username          = var.rds_username

  # Production: full Multi-AZ HA, deletion protection on, real final
  # snapshot taken on any destroy.
  multi_az                     = true
  backup_retention_period      = 30
  deletion_protection          = true
  skip_final_snapshot          = false
  performance_insights_enabled = true
}

module "elasticache" {
  source = "../../modules/elasticache"

  name_prefix                = var.name_prefix
  environment                = var.environment
  vpc_id                     = module.networking.vpc_id
  private_subnet_ids         = module.networking.private_subnet_ids
  eks_node_security_group_id = module.eks.node_security_group_id

  engine_version = var.redis_engine_version
  node_type      = var.redis_node_type

  # Production: 3-node replication group (1 primary + 2 replicas) across AZs
  # with automatic failover.
  num_cache_clusters         = 3
  multi_az_enabled           = true
  transit_encryption_enabled = true
  snapshot_retention_limit   = 7
}

module "ecr" {
  source = "../../modules/ecr"

  name_prefix      = var.name_prefix
  environment      = var.environment
  repository_names = var.ecr_repository_names

  image_tag_mutability       = "IMMUTABLE"
  untagged_image_expiry_days = 30
  tagged_image_count_limit   = 50
}
