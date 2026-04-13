# =============================================================================
# EKS Cluster — Elastic Kubernetes Service
# =============================================================================
#
# WHAT THIS CREATES:
#   1. EKS Control Plane — managed by AWS (API server, etcd, scheduler)
#   2. Managed Node Group — EC2 instances that run your pods
#   3. IAM Roles — for the cluster and nodes to interact with AWS services
#   4. Security Groups — network rules for cluster communication
#   5. Core Add-ons — coredns, kube-proxy, vpc-cni
#
# WHY MANAGED NODE GROUPS?
#   AWS handles node provisioning, patching, and lifecycle management.
#   You specify instance type and count; AWS handles the rest.
#   Alternative: Self-managed nodes or Fargate (serverless).
#
# COST BREAKDOWN (us-east-1, EKS 1.35 standard support):
#   - EKS control plane: $0.10/hr (~$73/month)
#   - 2x t3.medium nodes: $0.0416/hr each (~$60/month total)
#   - NAT Gateway: $0.045/hr + data (~$33/month)
#   - Total: ~$166/month  |  ~$5.50/day  |  ~$0.23/hr
#   - ⚠ USING OLDER VERSIONS (e.g., 1.29) costs $0.60/hr — 6x more!
#   - DELETE WHEN DONE: terraform destroy
# =============================================================================

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  # ─────────────────────────────────────────────────────────────────
  # Cluster Configuration
  # ─────────────────────────────────────────────────────────────────
  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  # Network — place the cluster in our VPC's private subnets
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Enable public access to the EKS API endpoint
  # This lets you run kubectl from your local machine
  # In production, restrict this with cluster_endpoint_public_access_cidrs
  cluster_endpoint_public_access = true

  # IRSA (IAM Roles for Service Accounts) is enabled by default in module v20
  # OIDC provider is created automatically — pods can assume IAM roles

  # ─────────────────────────────────────────────────────────────────
  # Cluster Add-ons (managed by AWS)
  # ─────────────────────────────────────────────────────────────────
  # These are essential components that every EKS cluster needs.
  # "most_recent = true" uses the latest compatible version.
  cluster_addons = {
    # CoreDNS: Provides DNS-based service discovery within the cluster
    coredns = {
      most_recent = true
    }
    # kube-proxy: Maintains network rules on nodes for Service routing
    kube-proxy = {
      most_recent = true
    }
    # vpc-cni: AWS VPC CNI plugin — assigns VPC IPs to pods
    vpc-cni = {
      most_recent = true
    }
  }

# ─────────────────────────────────────────────────────────────────
  # Security Group Rules for Istio
  # ─────────────────────────────────────────────────────────────────
  node_security_group_additional_rules = {
    ingress_istio_webhook = {
      description                   = "Allow EKS Control Plane to reach Istio webhook"
      protocol                      = "tcp"
      from_port                     = 15017
      to_port                       = 15017
      type                          = "ingress"
      source_cluster_security_group = true
    }
  }

  # ─────────────────────────────────────────────────────────────────
  # Managed Node Group — EC2 worker nodes
  # ─────────────────────────────────────────────────────────────────
  eks_managed_node_groups = {
    workers = {
      # Instance type: t3.medium = 2 vCPU, 4 GiB RAM
      # Sufficient for Istio sidecars + ML API pods + ArgoCD
      instance_types = [var.node_instance_type]

      # Scaling configuration
      min_size     = var.node_min_count
      max_size     = var.node_max_count
      desired_size = var.node_desired_count

      # Use Amazon Linux 2023 optimized for EKS
      ami_type = "AL2023_x86_64_STANDARD"

      # Labels applied to all nodes in this group
      # Useful for node affinity and pod scheduling
      labels = {
        role = "worker"
      }

      tags = {
        NodeGroup = "workers"
      }
    }
  }

  # ─────────────────────────────────────────────────────────────────
  # Access Configuration
  # ─────────────────────────────────────────────────────────────────
  # Allow the Terraform-executing IAM user/role to administer the cluster
  enable_cluster_creator_admin_permissions = true

  tags = {
    Cluster = var.cluster_name
  }
}
