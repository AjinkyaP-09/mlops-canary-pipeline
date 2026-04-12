# =============================================================================
# ECR — Elastic Container Registry
# =============================================================================
#
# WHY ECR?
#   EKS nodes need to pull container images from a registry.
#   ECR is AWS's managed container registry, providing:
#     - Native IAM authentication (no separate registry credentials)
#     - Automatic vulnerability scanning on push
#     - Lifecycle policies to clean up old images
#     - Same-region pulls are free and fast
#
# IMAGE TAGGING STRATEGY:
#   - ml-api:v1 → Stable (production) version
#   - ml-api:v2 → Canary (challenger) version
#   The K8s Deployments reference these tags directly.
# =============================================================================

resource "aws_ecr_repository" "ml_api" {
  name = var.ecr_repo_name

  # MUTABLE: Allows overwriting existing tags (e.g., push a new v1 image)
  # IMMUTABLE: Tags are permanent once pushed (safer for production)
  # We use MUTABLE for development flexibility
  image_tag_mutability = "MUTABLE"

  # Scan images for vulnerabilities automatically when pushed
  image_scanning_configuration {
    scan_on_push = true
  }

  # Allow terraform destroy to delete even if images exist
  force_delete = true

  tags = {
    Name = var.ecr_repo_name
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Lifecycle Policy — Automatically clean up old images
# ─────────────────────────────────────────────────────────────────────────────
# Keeps only the 10 most recent images. Older images are automatically deleted.
# This prevents the repository from growing indefinitely and incurring storage costs.
resource "aws_ecr_lifecycle_policy" "ml_api" {
  repository = aws_ecr_repository.ml_api.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep only the 10 most recent images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
