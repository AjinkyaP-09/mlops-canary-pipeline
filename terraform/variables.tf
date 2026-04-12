# =============================================================================
# Input Variables
# =============================================================================
# Variables make the infrastructure reusable and configurable without
# modifying the core Terraform code. Override defaults via:
#   - terraform.tfvars file
#   - CLI: terraform apply -var="cluster_name=my-cluster"
#   - Environment: TF_VAR_cluster_name=my-cluster
# =============================================================================

# ─────────────────────────────────────────────────────────────────────────────
# AWS Configuration
# ─────────────────────────────────────────────────────────────────────────────

variable "aws_region" {
  description = "AWS region to deploy all resources"
  type        = string
  default     = "us-east-1"
}

# ─────────────────────────────────────────────────────────────────────────────
# VPC Configuration
# ─────────────────────────────────────────────────────────────────────────────

variable "vpc_cidr" {
  description = "CIDR block for the VPC (e.g., 10.0.0.0/16 gives 65,536 IPs)"
  type        = string
  default     = "10.0.0.0/16"
}

# ─────────────────────────────────────────────────────────────────────────────
# EKS Cluster Configuration
# ─────────────────────────────────────────────────────────────────────────────

variable "cluster_name" {
  description = "Name of the EKS cluster (must be unique within the AWS account)"
  type        = string
  default     = "mlops-canary-cluster"
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster (use latest to avoid extended support charges)"
  type        = string
  default     = "1.35"
}

# ─────────────────────────────────────────────────────────────────────────────
# EKS Node Group Configuration
# ─────────────────────────────────────────────────────────────────────────────

variable "node_instance_type" {
  description = "EC2 instance type for EKS worker nodes (t3.medium = 2 vCPU, 4GB RAM)"
  type        = string
  default     = "t3.medium"
}

variable "node_desired_count" {
  description = "Desired number of worker nodes (normal operating state)"
  type        = number
  default     = 2
}

variable "node_min_count" {
  description = "Minimum number of worker nodes (2 needed for Istio + ArgoCD)"
  type        = number
  default     = 2
}

variable "node_max_count" {
  description = "Maximum number of worker nodes (caps auto-scaling)"
  type        = number
  default     = 3
}

# ─────────────────────────────────────────────────────────────────────────────
# ECR Configuration
# ─────────────────────────────────────────────────────────────────────────────

variable "ecr_repo_name" {
  description = "Name of the ECR repository for ML API container images"
  type        = string
  default     = "ml-api"
}
