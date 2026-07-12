resource "aws_subnet" "public" {
  count                   = local.az_count
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name                                           = "${var.name_prefix}-public-${var.azs[count.index]}"
    Tier                                           = "public"
    "kubernetes.io/cluster/${var.name_prefix}-eks" = "shared"
    "kubernetes.io/role/elb"                       = "1"
  })
}

resource "aws_subnet" "private" {
  count             = local.az_count
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = merge(local.common_tags, {
    Name                                           = "${var.name_prefix}-private-${var.azs[count.index]}"
    Tier                                           = "private"
    "kubernetes.io/cluster/${var.name_prefix}-eks" = "shared"
    "kubernetes.io/role/internal-elb"              = "1"
  })
}
