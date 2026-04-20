#!/bin/bash
set -euo pipefail

###############################################################################
# MCP Mimir — AKS Deployment Script
#
# Usage:
#   ./deploy.sh dev                    # Deploy to dev
#   ./deploy.sh perf                   # Deploy to perf
#   ./deploy.sh prod                   # Deploy to prod
#   ./deploy.sh dev --dry-run          # Preview rendered manifests
#   ./deploy.sh dev --delete           # Delete deployment
#   ./deploy.sh dev --validate         # Validate manifests only
#
# Environment Variables:
#   IMAGE_TAG     Override the image tag (default: v1.0.0-snapshot for dev/perf,
#                 v1.0.0 for prod)
#   ACR_REGISTRY  Override ACR registry (default: escoacrprod01.azurecr.io)
#   SKIP_BUILD    Set to "true" to skip Docker build+push
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV="${1:-}"
ACTION="${2:-apply}"

if [[ -z "$ENV" || ! "$ENV" =~ ^(dev|perf|prod)$ ]]; then
  echo "Usage: $0 <dev|perf|prod> [--dry-run|--delete|--validate]"
  echo ""
  echo "Options:"
  echo "  --dry-run    Render manifests without applying"
  echo "  --delete     Delete the deployment"
  echo "  --validate   Validate manifests against the cluster"
  echo ""
  echo "Environment variables:"
  echo "  IMAGE_TAG=v1.0.0     Override image tag"
  echo "  SKIP_BUILD=true      Skip Docker build & push"
  exit 1
fi

OVERLAY_DIR="$SCRIPT_DIR/overlays/$ENV"
ACR_REGISTRY="${ACR_REGISTRY:-escoacrprod01.azurecr.io}"
ACR_REPO="sample/sample-mimir-mcp"

# Default image tags per environment
case "$ENV" in
  dev)   DEFAULT_TAG="v1.0.0-snapshot" ; NAMESPACE="sample-dev"  ;;
  perf)  DEFAULT_TAG="v1.0.0-snapshot" ; NAMESPACE="sample-perf" ;;
  prod)  DEFAULT_TAG="v1.0.0"          ; NAMESPACE="sample-prod" ;;
esac

IMAGE_TAG="${IMAGE_TAG:-$DEFAULT_TAG}"
IMAGE="${ACR_REGISTRY}/${ACR_REPO}:${IMAGE_TAG}"

echo "============================================"
echo "  MCP Mimir — AKS Deployment"
echo "  Environment: $ENV"
echo "  Namespace:   $NAMESPACE"
echo "  Image:       $IMAGE"
echo "  Action:      $ACTION"
echo "============================================"
echo ""

# ── Verify kubectl context ──
CURRENT_CTX=$(kubectl config current-context 2>/dev/null || echo "none")
echo "kubectl context: $CURRENT_CTX"
echo ""

# ── Delete ──
if [[ "$ACTION" == "--delete" ]]; then
  echo ">>> Deleting $ENV deployment from namespace $NAMESPACE..."
  kubectl delete -k "$OVERLAY_DIR" --ignore-not-found -n "$NAMESPACE"
  echo ">>> Deleted."
  exit 0
fi

# ── Build & Push (unless skipped) ──
if [[ "$ACTION" != "--dry-run" && "$ACTION" != "--validate" && "${SKIP_BUILD:-false}" != "true" ]]; then
  echo ">>> Logging into ACR..."
  az acr login --name "${ACR_REGISTRY%%.*}" 2>/dev/null || echo "  (skipped — ensure you're logged in)"

  echo ">>> Building Docker image..."
  docker build -t "$IMAGE" "$SCRIPT_DIR/.."

  echo ">>> Pushing image to ACR..."
  docker push "$IMAGE"
  echo ">>> Image pushed: $IMAGE"
  echo ""
fi

cd "$OVERLAY_DIR"

# ── Render manifests with image substitution ──
RENDERED=$(kubectl kustomize . | sed "s|escoacrprod01.azurecr.io/sample/sample-mimir-mcp:[^ ]*|${IMAGE}|g")

# ── Dry run ──
if [[ "$ACTION" == "--dry-run" ]]; then
  echo ">>> Rendered manifests for $ENV:"
  echo "--------------------------------------------"
  echo "$RENDERED"
  exit 0
fi

# ── Validate only ──
if [[ "$ACTION" == "--validate" ]]; then
  echo ">>> Validating manifests against cluster..."
  echo "$RENDERED" | kubectl apply --dry-run=server -f - 2>&1
  echo ""
  echo ">>> Validation complete."
  exit 0
fi

# ── Ensure namespace exists ──
kubectl get namespace "$NAMESPACE" >/dev/null 2>&1 || {
  echo ">>> Creating namespace $NAMESPACE..."
  kubectl create namespace "$NAMESPACE"
  # Apply standard labels
  kubectl label namespace "$NAMESPACE" \
    appcode=SAMPLE \
    costcenter=9901623 \
    drcategory=dr3 \
    environment="$ENV" \
    portfolio=AI-CloudOps \
    project=SAMPLE \
    --overwrite
}

# ── Apply ──
echo ">>> Applying $ENV deployment to namespace $NAMESPACE..."
echo "$RENDERED" | kubectl apply -f -

echo ""
echo ">>> Waiting for rollout..."
kubectl rollout status deployment/sample-mcp-mimir -n "$NAMESPACE" --timeout=180s

echo ""
echo ">>> Deployment status:"
echo ""
echo "--- Pods ---"
kubectl get pods -n "$NAMESPACE" -l app=sample-mcp-mimir -o wide
echo ""
echo "--- Service ---"
kubectl get svc -n "$NAMESPACE" -l app=sample-mcp-mimir
echo ""
echo "--- VirtualService ---"
kubectl get virtualservice -n "$NAMESPACE" -l app=sample-mcp-mimir 2>/dev/null || echo "(no virtualservice found)"
echo ""
echo "--- PDB ---"
kubectl get pdb -n "$NAMESPACE" -l app=sample-mcp-mimir 2>/dev/null || echo "(no pdb found)"
echo ""
echo "--- AzureKeyVaultSecrets ---"
kubectl get azurekeyvaultsecret -n "$NAMESPACE" 2>/dev/null || echo "(akv2k8s not installed or no secrets)"

echo ""
echo "============================================"
echo "  Deployed to $ENV ($NAMESPACE) successfully!"
echo ""
echo "  Verify:"
echo "    kubectl logs -n $NAMESPACE -l app=sample-mcp-mimir -f"
echo "    kubectl port-forward -n $NAMESPACE svc/sample-mcp-mimir 8000:8000"
echo "============================================"
