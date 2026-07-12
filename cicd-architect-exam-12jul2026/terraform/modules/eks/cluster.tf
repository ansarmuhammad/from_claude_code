locals {
  common_tags = merge(
    {
      Environment = var.environment
      ManagedBy   = "terraform"
      Project     = "cicd-architect-exam"
    },
    var.tags
  )

  # EKS wants a single subnet list; combine private (worker/control-plane ENIs)
  # and public (for internet-facing load balancers) subnets.
  cluster_subnet_ids = concat(var.private_subnet_ids, var.public_subnet_ids)
}

resource "aws_security_group" "cluster" {
  name        = "${var.name_prefix}-eks-cluster-sg"
  description = "Security group for the EKS control plane ENIs."
  vpc_id      = var.vpc_id

  egress {
    description = "Allow all egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-eks-cluster-sg"
  })
}

resource "aws_eks_cluster" "this" {
  name     = "${var.name_prefix}-eks"
  role_arn = aws_iam_role.cluster.arn
  version  = var.cluster_version

  vpc_config {
    subnet_ids              = local.cluster_subnet_ids
    security_group_ids      = [aws_security_group.cluster.id]
    endpoint_private_access = var.endpoint_private_access
    endpoint_public_access  = var.endpoint_public_access
    public_access_cidrs     = var.public_access_cidrs
  }

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-eks"
  })

  depends_on = [
    aws_iam_role_policy_attachment.cluster_amazon_eks_cluster_policy,
  ]
}

# Security group applied to worker nodes; allows nodes to talk to each other
# and to the control plane, and is referenced by RDS/ElastiCache security
# groups to permit ingress from pods running on these nodes.
resource "aws_security_group" "node" {
  name        = "${var.name_prefix}-eks-node-sg"
  description = "Security group for EKS worker nodes / pods."
  vpc_id      = var.vpc_id

  egress {
    description = "Allow all egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name                                           = "${var.name_prefix}-eks-node-sg"
    "kubernetes.io/cluster/${var.name_prefix}-eks" = "owned"
  })
}

resource "aws_security_group_rule" "node_self_ingress" {
  description              = "Allow nodes to communicate with each other."
  type                     = "ingress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "-1"
  security_group_id        = aws_security_group.node.id
  source_security_group_id = aws_security_group.node.id
}

resource "aws_security_group_rule" "node_from_cluster" {
  description              = "Allow the control plane to reach kubelet/pods on nodes."
  type                     = "ingress"
  from_port                = 1025
  to_port                  = 65535
  protocol                 = "tcp"
  security_group_id        = aws_security_group.node.id
  source_security_group_id = aws_security_group.cluster.id
}

resource "aws_security_group_rule" "cluster_from_node" {
  description              = "Allow nodes to reach the control plane API."
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.cluster.id
  source_security_group_id = aws_security_group.node.id
}
