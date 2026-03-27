#!/bin/bash
set -euo pipefail

# ---------------------------------------------------------------
# MCP Prometheus — AKS Deployment Script
# Usage:
#   ./deploy.sh dev          # Deploy to dev
#   ./deploy.sh perf         # Deploy to perf
#   ./deploy.sh prod         # Deploy to prod
#   ./deploy.sh dev --dry-run  # Preview without applying
#   ./deploy.sh dev --delete   # Delete deployment
# ---------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV="${1:-}"
ACTION="${2:-apply}"

if [[ -z "$ENV" || ! "$ENV" =~ ^(dev|perf|prod)$ ]]; then
  echo "Usage: $0 <dev|perf|prod> [--dry-run|--delete]"
  exit 1
fi

OVERLAY_DIR="$SCRIPT_DIR/overlays/$ENV"
ACR_REGISTRY="${ACR_REGISTRY:-your-acr-name.azurecr.io}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
IMAGE="${ACR_REGISTRY}/mcp-prometheus:${IMAGE_TAG}"

echo "============================================"
echo "  MCP Prometheus — AKS Deployment"
echo "  Environment: $ENV"
echo "  Image:       $IMAGE"
echo "  Action:      $ACTION"
echo "============================================"

# Build and push image to ACR (skip for dry-run/delete)
if [[ "$ACTION" != "--dry-run" && "$ACTION" != "--delete" ]]; then
  echo ""
  echo ">>> Building and pushing Docker image to ACR..."
  docker build -t "$IMAGE" "$SCRIPT_DIR/.."
  docker push "$IMAGE"
  echo ">>> Image pushed: $IMAGE"
fi

# Set image in kustomization
cd "$OVERLAY_DIR"

if [[ "$ACTION" == "--delete" ]]; then
  echo ""
  echo ">>> Deleting $ENV deployment..."
  kubectl delete -k . --ignore-not-found
  echo ">>> Deleted."
  exit 0
fi

if [[ "$ACTION" == "--dry-run" ]]; then
  echo ""
  echo ">>> Dry run — rendered manifests for $ENV:"
  echo "--------------------------------------------"
  kubectl kustomize . | sed "s|mcp-prometheus:latest|${IMAGE}|g"
  exit 0
fi

# Apply
echo ""
echo ">>> Applying $ENV deployment..."
kubectl kustomize . | sed "s|mcp-prometheus:latest|${IMAGE}|g" | kubectl apply -f -

echo ""
echo ">>> Waiting for rollout..."
NAMESPACE="mcp-prometheus-${ENV}"
DEPLOY_NAME="mcp-prometheus"
kubectl rollout status deployment/"$DEPLOY_NAME" -n "$NAMESPACE" --timeout=120s

echo ""
echo ">>> Deployment status:"
kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=mcp-prometheus
echo ""
kubectl get svc -n "$NAMESPACE" -l app.kubernetes.io/name=mcp-prometheus
echo ""
kubectl get ingress -n "$NAMESPACE" -l app.kubernetes.io/name=mcp-prometheus

echo ""
echo "============================================"
echo "  Deployed to $ENV successfully!"
echo "============================================"
