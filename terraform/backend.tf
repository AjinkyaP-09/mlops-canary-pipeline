# =============================================================================
# Terraform Remote Backend — S3 + DynamoDB State Locking
# =============================================================================
#
# WHY REMOTE STATE?
#   By default, Terraform stores state in a local file (terraform.tfstate).
#   This is problematic because:
#     1. State contains sensitive data (passwords, endpoints) — shouldn't be in Git
#     2. Multiple team members can't work simultaneously (state conflicts)
#     3. Local state can be lost if your machine crashes
#
#   S3 backend solves all of these:
#     - State is encrypted at rest in S3
#     - DynamoDB table provides state LOCKING to prevent concurrent modifications
#     - State is versioned (S3 versioning) for easy rollback
#
# BOOTSTRAP (one-time):
#   The S3 bucket must exist BEFORE running `terraform init`.
#   The bucket "meme-cricket-tf-state-store" already exists in your account.
#
#   If the DynamoDB table doesn't exist yet, create it:
#     aws dynamodb create-table \
#       --table-name mlops-canary-tf-lock \
#       --attribute-definitions AttributeName=LockID,AttributeType=S \
#       --key-schema AttributeName=LockID,KeyType=HASH \
#       --billing-mode PAY_PER_REQUEST \
#       --region us-east-1
#
# NOTE: Backend config blocks cannot use variables — all values must be hardcoded.
# =============================================================================

terraform {
  backend "s3" {
    # S3 bucket for storing state (must already exist)
    bucket = "meme-cricket-tf-state-store"

    # Key (path) within the bucket — organizes state for multiple projects
    key = "mlops-canary-pipeline/terraform.tfstate"

    # Region where the S3 bucket lives
    region = "us-east-1"

    # Encrypt state file at rest using SSE-S3
    encrypt = true

    # DynamoDB table for state locking (prevents concurrent modifications)
    dynamodb_table = "mlops-canary-tf-lock"
  }
}
