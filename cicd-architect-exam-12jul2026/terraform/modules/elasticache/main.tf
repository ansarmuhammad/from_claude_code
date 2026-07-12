locals {
  common_tags = merge(
    {
      Environment = var.environment
      ManagedBy   = "terraform"
      Project     = "cicd-architect-exam"
    },
    var.tags
  )

  # Automatic failover requires Multi-AZ and at least 2 nodes in the group.
  automatic_failover_enabled = var.multi_az_enabled && var.num_cache_clusters > 1
}

resource "aws_elasticache_subnet_group" "this" {
  name       = "${var.name_prefix}-redis-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-redis-subnet-group"
  })
}

resource "aws_security_group" "redis" {
  name        = "${var.name_prefix}-redis-sg"
  description = "Security group for the ${var.name_prefix} ElastiCache Redis replication group."
  vpc_id      = var.vpc_id

  egress {
    description = "Allow all egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-redis-sg"
  })
}

resource "aws_security_group_rule" "redis_from_eks" {
  description              = "Allow Redis access from EKS nodes/pods."
  type                     = "ingress"
  from_port                = var.port
  to_port                  = var.port
  protocol                 = "tcp"
  security_group_id        = aws_security_group.redis.id
  source_security_group_id = var.eks_node_security_group_id
}

resource "aws_elasticache_parameter_group" "this" {
  name   = "${var.name_prefix}-redis7-params"
  family = "redis7"

  parameter {
    name  = "maxmemory-policy"
    value = "allkeys-lru"
  }
}

# A single replication group resource covers both shapes:
#  - dev: num_cache_clusters = 1 -> single node, no automatic failover
#  - staging/production: num_cache_clusters >= 2, multi_az_enabled = true -> HA with automatic failover
resource "aws_elasticache_replication_group" "this" {
  replication_group_id = "${var.name_prefix}-redis"
  description          = "Redis replication group for ${var.name_prefix} (${var.environment})."

  engine         = "redis"
  engine_version = var.engine_version
  node_type      = var.node_type
  port           = var.port

  parameter_group_name = aws_elasticache_parameter_group.this.name
  subnet_group_name    = aws_elasticache_subnet_group.this.name
  security_group_ids   = [aws_security_group.redis.id]

  num_cache_clusters         = var.num_cache_clusters
  automatic_failover_enabled = local.automatic_failover_enabled
  multi_az_enabled           = local.automatic_failover_enabled

  at_rest_encryption_enabled = var.at_rest_encryption_enabled
  transit_encryption_enabled = var.transit_encryption_enabled

  snapshot_retention_limit = var.snapshot_retention_limit
  apply_immediately        = var.environment != "production"

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-redis"
  })
}
