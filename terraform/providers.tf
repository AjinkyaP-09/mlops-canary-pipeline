# =============================================================================
# Terraform & Provider Configuration
# =============================================================================
# This file declares the required Terraform version, provider versions,
# and configures the AWS provider.
#
# WHY PIN VERSIONS?
#   Provider updates can introduce breaking changes. Pinning ensures
#   your infrastructure code works consistently across team members
#   and CI/CD pipelines.
# =============================================================================

terraform {
  # Minimum Terraform CLI version required
  required_version = ">= 1.5.0"

  required_providers {
    # AWS provider — manages all AWS resources (VPC, EKS, ECR, etc.)
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Configure the AWS provider
# Credentials are read from environment variables (AWS_ACCESS_KEY_ID,
# AWS_SECRET_ACCESS_KEY) or from ~/.aws/credentials profile.
# NEVER hardcode credentials in Terraform files.
provider "aws" {
  region = var.aws_region

  # Default tags applied to ALL resources created by this provider.
  # This makes cost tracking and resource identification easy.
  default_tags {
    tags = {
      Project     = "mlops-canary-pipeline"
      ManagedBy   = "terraform"
      Environment = "production"
    }
  }
}
