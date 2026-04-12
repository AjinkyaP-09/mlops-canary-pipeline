#!/bin/bash
# =============================================================================
# Canary Deployment Traffic Test (EKS)
# =============================================================================
# Sends requests through the Istio Ingress Gateway to verify
# the 90/10 traffic split between v1 (stable) and v2 (canary).
# =============================================================================

set -uo pipefail

NUM_REQUESTS=200
EXPECTED_V1_PERCENT=90
EXPECTED_V2_PERCENT=10
TOLERANCE=8

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[✓]${NC} $1"; }
error()   { echo -e "${RED}[✗]${NC} $1" >&2; }

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}${CYAN}  CANARY DEPLOYMENT TRAFFIC TEST${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Get Istio Ingress Gateway URL (EKS LoadBalancer)
info "Discovering Istio Ingress Gateway URL..."
INGRESS_HOST=$(kubectl get svc istio-ingressgateway -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)

if [ -z "$INGRESS_HOST" ]; then
    INGRESS_HOST=$(kubectl get svc istio-ingressgateway -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
fi

if [ -z "$INGRESS_HOST" ]; then
    error "Could not determine Istio Ingress Gateway URL."
    error "Check: kubectl get svc istio-ingressgateway -n istio-system"
    exit 1
fi

INGRESS_URL="http://${INGRESS_HOST}"
success "Ingress URL: ${INGRESS_URL}"
echo ""

# Health check
info "Testing health endpoint (GET /)..."
HEALTH=$(curl -s --max-time 10 "${INGRESS_URL}/")
if [ $? -ne 0 ]; then
    error "Health check failed! Check pods: kubectl get pods -l app=ml-api"
    exit 1
fi
success "Health: ${HEALTH}"
echo ""

# Send traffic
info "Sending ${NUM_REQUESTS} requests to POST /predict ..."
V1_COUNT=0; V2_COUNT=0; ERROR_COUNT=0
PROGRESS_STEP=$((NUM_REQUESTS / 20))

for i in $(seq 1 $NUM_REQUESTS); do
    RESPONSE=$(curl -s --max-time 5 -X POST -H "Content-Type: application/json" \
        -d '{"features": [1.5, 2.3, 4.7, 0.8]}' "${INGRESS_URL}/predict" 2>/dev/null)

    if echo "$RESPONSE" | grep -q '"v1"'; then
        V1_COUNT=$((V1_COUNT + 1))
    elif echo "$RESPONSE" | grep -q '"v2"'; then
        V2_COUNT=$((V2_COUNT + 1))
    else
        ERROR_COUNT=$((ERROR_COUNT + 1))
    fi

    if [ $((i % PROGRESS_STEP)) -eq 0 ]; then
        PERCENT=$((i * 100 / NUM_REQUESTS))
        printf "\r  ${BLUE}Progress: %3d%% (%d/${NUM_REQUESTS})${NC}" "$PERCENT" "$i"
    fi
done
echo ""
echo ""

# Results
TOTAL=$((V1_COUNT + V2_COUNT))
if [ $TOTAL -eq 0 ]; then error "No successful responses!"; exit 1; fi

ACTUAL_V1=$((V1_COUNT * 100 / TOTAL))
ACTUAL_V2=$((V2_COUNT * 100 / TOTAL))

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}  RESULTS${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
printf "  %-14s %-10s %-10s %-10s\n" "Version" "Count" "Actual%" "Expected%"
printf "  %-14s %-10s %-10s %-10s\n" "──────────" "────────" "────────" "────────"
printf "  ${GREEN}%-14s${NC} %-10s %-10s %-10s\n" "v1 (stable)" "$V1_COUNT" "${ACTUAL_V1}%" "${EXPECTED_V1_PERCENT}%"
printf "  ${YELLOW}%-14s${NC} %-10s %-10s %-10s\n" "v2 (canary)" "$V2_COUNT" "${ACTUAL_V2}%" "${EXPECTED_V2_PERCENT}%"
echo "  Errors: ${ERROR_COUNT}"
echo ""

V1_DIFF=$((ACTUAL_V1 - EXPECTED_V1_PERCENT)); V1_DIFF=${V1_DIFF#-}
if [ "$V1_DIFF" -le "$TOLERANCE" ]; then
    echo -e "  ${GREEN}${BOLD}✅ CANARY TEST PASSED${NC} — within ${TOLERANCE}% tolerance"
else
    echo -e "  ${RED}${BOLD}❌ CANARY TEST FAILED${NC} — ${V1_DIFF}% deviation (tolerance: ${TOLERANCE}%)"
fi
echo ""
echo -e "  ${BOLD}Observe:${NC} kubectl port-forward svc/kiali -n istio-system 20001:20001"
echo -e "         Open http://localhost:20001 → Graph → default namespace"
echo ""
