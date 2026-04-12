# =============================================================================
# Terraform Outputs
# =============================================================================
# Outputs are displayed after `terraform apply` and can be queried with
# `terraform output <name>`. The deploy.sh script uses these to configure
# kubectl, push images to ECR, and update Kubernetes manifests.
# =============================================================================

output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS cluster API endpoint URL"
  value       = module.eks.cluster_endpoint
  sensitive   = true
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate for EKS cluster CA"
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "ecr_repository_url" {
  description = "ECR repository URL for pushing/pulling ML API images"
  value       = aws_ecr_repository.ml_api.repository_url
}

output "region" {
  description = "AWS region where resources are deployed"
  value       = var.aws_region
}

output "vpc_id" {
  description = "ID of the VPC hosting the EKS cluster"
  value       = module.vpc.vpc_id
}

# ─────────────────────────────────────────────────────────────────────────────
# Helper commands — printed after terraform apply for easy copy-paste
# ─────────────────────────────────────────────────────────────────────────────

output "configure_kubectl" {
  description = "Command to configure kubectl for this cluster"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}

output "ecr_login" {
  description = "Command to authenticate Docker with ECR"
  value       = "aws ecr get-login-password --region ${var.aws_region} | docker login --username AWS --password-stdin ${aws_ecr_repository.ml_api.repository_url}"
}
