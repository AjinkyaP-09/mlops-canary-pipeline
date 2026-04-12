# GitOps-Driven MLOps Pipeline: Automated Canary Rollouts with ArgoCD & Istio

[![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?style=flat&logo=kubernetes&logoColor=white)](https://kubernetes.io/)
[![Istio](https://img.shields.io/badge/Istio-466BB0?style=flat&logo=istio&logoColor=white)](https://istio.io/)
[![ArgoCD](https://img.shields.io/badge/ArgoCD-EF7B4D?style=flat&logo=argo&logoColor=white)](https://argoproj.github.io/cd/)
[![Terraform](https://img.shields.io/badge/Terraform-7B42BC?style=flat&logo=terraform&logoColor=white)](https://www.terraform.io/)
[![AWS EKS](https://img.shields.io/badge/AWS_EKS-FF9900?style=flat&logo=amazoneks&logoColor=white)](https://aws.amazon.com/eks/)
[![FastAPI](https://img.shields.io/badge/FastAPI-009688?style=flat&logo=fastapi&logoColor=white)](https://fastapi.tiangolo.com/)
[![GitHub Actions](https://img.shields.io/badge/GitHub_Actions-2088FF?style=flat&logo=githubactions&logoColor=white)](https://github.com/features/actions)

A production-grade POC demonstrating **canary deployments** of an ML API on **AWS EKS** using **Terraform** (IaC), **ArgoCD** (GitOps), and **Istio** (service mesh) — with full observability via Kiali and Grafana.

---

## Architecture

```
                           ┌──────────────┐
                           │   GitHub     │
                           │   Repo       │
                           └──────┬───────┘
                                  │ watches
                           ┌──────▼───────┐
                           │   ArgoCD     │
                           │   (GitOps)   │
                           └──────┬───────┘
                                  │ syncs k8s-manifests/
                    ┌─────────────▼──────────────────┐
                    │      AWS EKS Cluster            │
                    │                                 │
    External  ──→ [AWS ELB] ──→ [Istio Ingress GW]  │
                         │                           │
                  [VirtualService 90/10]             │
                  90% ↙        ↘ 10%                │
              [v1 Pods]      [v2 Pods]              │
              (Stable)       (Canary)               │
                    │                                 │
                    └─────────────────────────────────┘

Infrastructure provisioned by Terraform:
  VPC → Subnets → NAT GW → EKS → ECR → IAM Roles
```

---

## Project Structure

```
mlops-canary-pipeline/
├── app/                          # ML API application
│   ├── app.py                    # FastAPI prediction service
│   ├── Dockerfile                # Container image (pushed to ECR)
│   └── requirements.txt          # Pinned Python dependencies
│
├── terraform/                    # Infrastructure as Code
│   ├── providers.tf              # AWS provider + version constraints
│   ├── backend.tf                # S3 + DynamoDB state management
│   ├── variables.tf              # Input variables (region, instance type, etc.)
│   ├── vpc.tf                    # VPC, subnets, NAT gateway
│   ├── eks.tf                    # EKS cluster + managed node group
│   ├── ecr.tf                    # ECR repository + lifecycle policy
│   └── outputs.tf                # Cluster endpoint, ECR URL, kubectl cmd
│
├── k8s-manifests/                # ← ArgoCD syncs this directory
│   ├── k8s-deployments.yaml      # v1 (2 replicas) + v2 (1 replica) + Service
│   └── istio-canary.yaml         # Gateway + DestinationRule + VirtualService
│
├── argocd-setup/
│   └── argocd-app.yaml           # ArgoCD Application CRD
│
├── scripts/
│   ├── deploy.sh                 # Post-Terraform: Istio + ArgoCD + ECR images
│   └── test-canary.sh            # Traffic test with 90/10 verification
│
├── .github/workflows/            # CI/CD Pipelines (GitHub Actions)
│   ├── infra.yml                 # Terraform apply/destroy with choice parameter
│   └── deploy.yml                # Build, push, deploy full stack to EKS
│
├── .gitignore
└── README.md
```

---

## Quick Start

### 1. Provision Infrastructure

```bash
cd terraform/
terraform init
terraform plan
terraform apply    # ~15-20 minutes for EKS
```

### 2. Deploy Application Stack

```bash
cd ..
chmod +x scripts/deploy.sh
./scripts/deploy.sh
```

This installs Istio, ArgoCD, builds/pushes Docker images to ECR, and applies the ArgoCD Application.

### 3. Test Canary Split

```bash
chmod +x scripts/test-canary.sh
./scripts/test-canary.sh
```

Expected: ~90% v1 responses, ~10% v2 responses.

### 4. Access Dashboards

| Service | Access |
|---------|--------|
| **ML API** | `curl http://<ISTIO-ELB-URL>/predict` |
| **ArgoCD UI** | `https://<ARGOCD-ELB-URL>` (admin / auto-generated password) |
| **Kiali** | `kubectl port-forward svc/kiali -n istio-system 20001:20001` |
| **Grafana** | `kubectl port-forward svc/grafana -n istio-system 3000:3000` |

### 5. Cleanup (Avoid Charges!)

```bash
cd terraform/
terraform destroy    # Deletes ALL AWS resources
```

---

## GitOps Workflow

```bash
# Change canary weight (e.g., 90/10 → 50/50)
# Edit k8s-manifests/istio-canary.yaml

git add . && git commit -m "increase canary to 50%" && git push

# ArgoCD detects change → auto-syncs → Istio updates routing
# No kubectl needed. Full audit trail in Git.
```

---

## CI/CD Pipelines (GitHub Actions)

Both pipelines are triggered manually via `workflow_dispatch` (GitHub → Actions → Run workflow).

| Pipeline | File | Purpose |
|----------|------|---------|
| **Infrastructure** | `.github/workflows/infra.yml` | Terraform apply/destroy with choice parameter |
| **Application** | `.github/workflows/deploy.yml` | Build images → Push ECR → Install Istio/ArgoCD → Deploy |

**Required GitHub Secrets:**
```
AWS_ACCESS_KEY_ID       # IAM user access key
AWS_SECRET_ACCESS_KEY   # IAM user secret key
```

**Infrastructure Pipeline Inputs:**
- `action`: `apply` (create) or `destroy` (tear down)
- `aws_region`: AWS region (default: us-east-1)

**Application Pipeline Inputs:**
- `build_images`: Build and push Docker images (default: true)
- `install_istio`: Install Istio service mesh (default: true)
- `install_argocd`: Install ArgoCD (default: true)

---

## Key Technologies

| Technology | Purpose |
|-----------|---------|
| **Terraform** | Provisions VPC, EKS, ECR as code (S3 backend) |
| **AWS EKS** | Managed Kubernetes cluster |
| **AWS ECR** | Container image registry with auto-scanning |
| **Istio** | Service mesh — canary routing, mTLS, telemetry |
| **ArgoCD** | GitOps — auto-syncs Git ↔ cluster state |
| **GitHub Actions** | CI/CD — infrastructure and app deployment pipelines |
| **FastAPI** | ML prediction API (Python) |
| **Prometheus + Grafana** | Metrics collection and dashboards |
| **Kiali** | Real-time service mesh traffic visualization |

---

## Documentation

| Document | Description |
|----------|-------------|
| [Core Concepts](docs/01-core-concepts.md) | K8s, Istio, GitOps, Canary, Terraform, EKS, Observability |
| [Architecture Guide](docs/02-architecture-guide.md) | System design, traffic flow, component interactions |
| [Step-by-Step Guide](docs/03-step-by-step-guide.md) | Complete EKS deployment walkthrough |
| [Interview Prep](docs/04-interview-prep.md) | 30 questions with detailed answers |
| [Terraform Guide](docs/05-terraform-guide.md) | Infrastructure code deep-dive |

---

## Cost Estimate

| Component | Monthly Cost |
|-----------|-------------|
| EKS Control Plane | ~$73 |
| 2x t3.medium Nodes | ~$60 |
| NAT Gateway | ~$33 |
| **Total** | **~$166/month** |

> ⚠️ Run `terraform destroy` when done to stop all charges.

---

## License

This project is for educational and portfolio purposes.
