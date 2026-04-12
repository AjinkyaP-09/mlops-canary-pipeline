#!/bin/bash
# =============================================================================
# Post-Terraform Deployment Script
# =============================================================================
# RUN THIS AFTER: terraform apply (EKS cluster must be running)
#
# This script:
#   1. Configures kubectl for the EKS cluster
#   2. Builds & pushes Docker images to ECR
#   3. Updates k8s-manifests with ECR image URLs
#   4. Installs Istio on EKS
#   5. Installs Istio observability addons
#   6. Installs ArgoCD
#   7. Applies the ArgoCD Application
#   8. Prints access URLs
#
# PREREQUISITES:
#   - terraform apply completed successfully
#   - AWS CLI configured with valid credentials
#   - Docker running locally
#   - istioctl installed
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[✓]${NC} $1"; }
warn()    { echo -e "${YELLOW}[⚠]${NC} $1"; }
error()   { echo -e "${RED}[✗]${NC} $1" >&2; }

section() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${CYAN}  $1${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 0: Get Terraform Outputs
# ─────────────────────────────────────────────────────────────────────────────
section "0. Reading Terraform Outputs"

cd "$(dirname "$0")/../terraform"

ECR_URL=$(terraform output -raw ecr_repository_url 2>/dev/null)
REGION=$(terraform output -raw region 2>/dev/null)
CLUSTER_NAME=$(terraform output -raw cluster_name 2>/dev/null)

if [ -z "$ECR_URL" ] || [ -z "$REGION" ] || [ -z "$CLUSTER_NAME" ]; then
    error "Could not read Terraform outputs. Run 'terraform apply' first."
    exit 1
fi

success "ECR URL: ${ECR_URL}"
success "Region: ${REGION}"
success "Cluster: ${CLUSTER_NAME}"

cd "$(dirname "$0")/.."

# ─────────────────────────────────────────────────────────────────────────────
# Step 1: Configure kubectl
# ─────────────────────────────────────────────────────────────────────────────
section "1. Configuring kubectl for EKS"

aws eks update-kubeconfig --region "${REGION}" --name "${CLUSTER_NAME}"
success "kubectl configured!"
info "Nodes:"
kubectl get nodes

# ─────────────────────────────────────────────────────────────────────────────
# Step 2: Build & Push Docker Images to ECR
# ─────────────────────────────────────────────────────────────────────────────
section "2. Building & Pushing Docker Images to ECR"

info "Authenticating Docker with ECR..."
aws ecr get-login-password --region "${REGION}" | docker login --username AWS --password-stdin "${ECR_URL}"

info "Building ml-api:v1 (Stable)..."
docker build -t "${ECR_URL}:v1" ./app/

info "Building ml-api:v2 (Canary)..."
docker build -t "${ECR_URL}:v2" ./app/

info "Pushing images to ECR..."
docker push "${ECR_URL}:v1"
docker push "${ECR_URL}:v2"

success "Images pushed to ECR!"

# ─────────────────────────────────────────────────────────────────────────────
# Step 3: Update K8s Manifests with ECR URL
# ─────────────────────────────────────────────────────────────────────────────
section "3. Updating K8s Manifests with ECR URL"

sed -i "s|REPLACE_ECR_REPO_URL|${ECR_URL}|g" k8s-manifests/k8s-deployments.yaml
success "k8s-deployments.yaml updated with ECR URL: ${ECR_URL}"

# ─────────────────────────────────────────────────────────────────────────────
# Step 4: Install Istio
# ─────────────────────────────────────────────────────────────────────────────
section "4. Installing Istio Service Mesh"

info "Installing Istio with default profile..."
istioctl install --set profile=default -y

info "Labeling default namespace for sidecar injection..."
kubectl label namespace default istio-injection=enabled --overwrite

success "Istio installed!"

# ─────────────────────────────────────────────────────────────────────────────
# Step 5: Install Observability Add-ons
# ─────────────────────────────────────────────────────────────────────────────
section "5. Installing Observability Stack"

# Detect installed Istio version and derive release branch
ISTIO_VER=$(istioctl version --remote=false 2>/dev/null | head -1 | grep -oP '^\d+\.\d+' || echo "1.24")
ISTIO_RELEASE="release-${ISTIO_VER}"
info "Detected Istio version: ${ISTIO_VER} → using ${ISTIO_RELEASE} addons"

for ADDON in prometheus grafana kiali jaeger; do
    info "Installing ${ADDON}..."
    kubectl apply -f "https://raw.githubusercontent.com/istio/istio/${ISTIO_RELEASE}/samples/addons/${ADDON}.yaml" 2>/dev/null || \
    kubectl apply -f "https://raw.githubusercontent.com/istio/istio/master/samples/addons/${ADDON}.yaml" 2>/dev/null || \
    warn "${ADDON} install failed — install manually later"
done

info "Waiting for addons..."
kubectl rollout status deployment/prometheus -n istio-system --timeout=120s 2>/dev/null || true
kubectl rollout status deployment/grafana -n istio-system --timeout=120s 2>/dev/null || true
kubectl rollout status deployment/kiali -n istio-system --timeout=120s 2>/dev/null || true

success "Observability stack installed!"

# ─────────────────────────────────────────────────────────────────────────────
# Step 6: Install ArgoCD
# ─────────────────────────────────────────────────────────────────────────────
section "6. Installing ArgoCD"

kubectl create namespace argocd 2>/dev/null || warn "Namespace 'argocd' already exists"
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

info "Waiting for ArgoCD server..."
kubectl rollout status deployment/argocd-server -n argocd --timeout=300s

# Patch to LoadBalancer for EKS (gets an AWS ELB)
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'

success "ArgoCD installed!"

# ─────────────────────────────────────────────────────────────────────────────
# Step 7: Commit & Push Updated Manifests
# ─────────────────────────────────────────────────────────────────────────────
section "7. Committing Updated Manifests to Git"

info "Committing ECR URL update to Git..."
git add k8s-manifests/k8s-deployments.yaml
git commit -m "chore: update image URLs to ECR repository" 2>/dev/null || warn "Nothing to commit"
git push origin main 2>/dev/null || warn "Push failed — push manually"

success "Manifests pushed to Git!"

# ─────────────────────────────────────────────────────────────────────────────
# Step 8: Apply ArgoCD Application
# ─────────────────────────────────────────────────────────────────────────────
section "8. Deploying via ArgoCD"

kubectl apply -f argocd-setup/argocd-app.yaml
success "ArgoCD Application created!"

info "Waiting for sync..."
sleep 10
kubectl get applications -n argocd

# ─────────────────────────────────────────────────────────────────────────────
# Step 9: Summary
# ─────────────────────────────────────────────────────────────────────────────
section "✅ Deployment Complete!"

ARGO_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d 2>/dev/null || echo "N/A")
ARGO_LB=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "pending...")
ISTIO_LB=$(kubectl get svc istio-ingressgateway -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "pending...")

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}${GREEN}  ACCESS URLS${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  ${BOLD}ML API (Istio Ingress):${NC}"
echo -e "    ${CYAN}http://${ISTIO_LB}/${NC}"
echo -e "    curl -X POST -H 'Content-Type: application/json' -d '{\"features\":[1.5,2.3]}' http://${ISTIO_LB}/predict"
echo ""
echo -e "  ${BOLD}ArgoCD UI:${NC}"
echo -e "    ${CYAN}https://${ARGO_LB}${NC}"
echo -e "    Username: admin"
echo -e "    Password: ${YELLOW}${ARGO_PASSWORD}${NC}"
echo ""
echo -e "  ${BOLD}Kiali:${NC} kubectl port-forward svc/kiali -n istio-system 20001:20001"
echo -e "  ${BOLD}Grafana:${NC} kubectl port-forward svc/grafana -n istio-system 3000:3000"
echo ""
echo -e "  ${BOLD}Test Canary:${NC} ./scripts/test-canary.sh"
echo ""
echo -e "${RED}  ⚠ REMEMBER: Run 'terraform destroy' when done to avoid charges!${NC}"
echo ""
