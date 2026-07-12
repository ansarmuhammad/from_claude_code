locals {
  common_tags = merge(
    {
      Environment = var.environment
      ManagedBy   = "terraform"
      Project     = "cicd-architect-exam"
    },
    var.tags
  )

  repos = toset(var.repository_names)
}

resource "aws_ecr_repository" "this" {
  for_each = local.repos

  name                 = "${var.name_prefix}/${each.value}"
  image_tag_mutability = var.image_tag_mutability

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  tags = merge(local.common_tags, {
    Name    = "${var.name_prefix}-${each.value}"
    Service = each.value
  })
}

resource "aws_ecr_lifecycle_policy" "this" {
  for_each = local.repos

  repository = aws_ecr_repository.this[each.key].name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after ${var.untagged_image_expiry_days} days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.untagged_image_expiry_days
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Keep only the most recent ${var.tagged_image_count_limit} tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v", "sha-", "dev-", "main-", "develop-"]
          countType     = "imageCountMoreThan"
          countNumber   = var.tagged_image_count_limit
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
