module "networking" {
  source = "../../modules/networking"

  name_prefix          = var.name_prefix
  environment          = var.environment
  vpc_cidr             = var.vpc_cidr
  azs                  = var.azs
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs

  # Dev is cost-optimized: a single shared NAT Gateway instead of one per AZ.
  single_nat_gateway = true
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
  node_disk_size      = 30

  # Dev keeps the public endpoint open for convenience; staging/production
  # tighten this down.
  endpoint_public_access = true
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

  # Dev: single-AZ, minimal retention, no deletion protection.
  multi_az                = false
  backup_retention_period = 1
  deletion_protection     = false
  skip_final_snapshot     = true
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

  # Dev: single node, no HA/failover.
  num_cache_clusters       = 1
  multi_az_enabled         = false
  snapshot_retention_limit = 0
}

module "ecr" {
  source = "../../modules/ecr"

  name_prefix      = var.name_prefix
  environment      = var.environment
  repository_names = var.ecr_repository_names

  # Dev: mutable tags are convenient for iterating; staging/production use
  # immutable tags.
  image_tag_mutability       = "MUTABLE"
  untagged_image_expiry_days = 7
  tagged_image_count_limit   = 15
}
