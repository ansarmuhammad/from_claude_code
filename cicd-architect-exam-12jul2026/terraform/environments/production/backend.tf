terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # --- Remote state backend (S3 + DynamoDB lock table) ---
  #
  # PREREQUISITE (out of band, before first `terraform init`):
  #   1. Create the S3 bucket below with versioning + encryption enabled.
  #   2. Create the DynamoDB table below with a String partition key "LockID".
  # See terraform/README.md for the exact one-time bootstrap commands.
  #
  # Bucket/table names here are placeholders - replace with your organization's
  # actual state bucket/table before running `terraform init` for real.
  backend "s3" {
    bucket         = "cicd-architect-exam-tfstate-REPLACE_ME"
    key            = "env:/production/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "cicd-architect-exam-tf-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = "production"
      ManagedBy   = "terraform"
      Project     = "cicd-architect-exam"
    }
  }
}
