# =============================================================================
# VPC — Virtual Private Cloud
# =============================================================================
#
# WHY A DEDICATED VPC?
#   EKS needs isolated networking. A dedicated VPC provides:
#     - Network isolation from other workloads
#     - Control over IP ranges and subnets
#     - Proper security group boundaries
#
# SUBNET STRATEGY:
#   ┌─────────────────────────────────────────────────────────────────┐
#   │  Subnet Type    │  Purpose                                      │
#   │─────────────────│─────────────────────────────────────────────── │
#   │  Private (x2)   │  EKS worker nodes run here (no public IPs)   │
#   │  Public (x2)    │  NAT Gateway + Load Balancers (Istio Ingress) │
#   └─────────────────────────────────────────────────────────────────┘
#
#   Worker nodes in private subnets access the internet via NAT Gateway
#   (for pulling container images from ECR). This is a security best practice.
#
# TAGS:
#   EKS requires specific tags on subnets for auto-discovery:
#   - "kubernetes.io/cluster/<name>" = "shared" — marks subnets for EKS
#   - "kubernetes.io/role/elb" = 1 — public subnets (for internet-facing LBs)
#   - "kubernetes.io/role/internal-elb" = 1 — private subnets (for internal LBs)
# =============================================================================

# Discover available AZs in the selected region.
# EKS requires subnets in at least 2 AZs for high availability.
data "aws_availability_zones" "available" {
  state = "available"

  # Exclude Local Zones (they don't support all EKS features)
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  # VPC identifiers
  name = "${var.cluster_name}-vpc"
  cidr = var.vpc_cidr

  # Deploy across 2 availability zones for high availability
  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  # Private subnets — for EKS worker nodes
  # Nodes run here without public IPs (more secure)
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]

  # Public subnets — for NAT Gateway and external Load Balancers
  # Istio Ingress Gateway's AWS ALB/NLB is placed here
  public_subnets = ["10.0.101.0/24", "10.0.102.0/24"]

  # ─────────────────────────────────────────────────────────────────
  # NAT Gateway — enables private subnet internet access
  # ─────────────────────────────────────────────────────────────────
  # Nodes in private subnets need internet access to pull images from ECR.
  # single_nat_gateway = true → one NAT GW (cheaper, fine for non-prod).
  # For production HA, set to false + one_nat_gateway_per_az = true.
  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true
  enable_dns_support   = true

  # ─────────────────────────────────────────────────────────────────
  # EKS-required subnet tags
  # ─────────────────────────────────────────────────────────────────
  # These tags let EKS auto-discover subnets for node placement
  # and AWS Load Balancer Controller for ingress.

  public_subnet_tags = {
    "kubernetes.io/role/elb"                        = 1
    "kubernetes.io/cluster/${var.cluster_name}"      = "shared"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"               = 1
    "kubernetes.io/cluster/${var.cluster_name}"      = "shared"
  }

  tags = {
    Cluster = var.cluster_name
  }
}
