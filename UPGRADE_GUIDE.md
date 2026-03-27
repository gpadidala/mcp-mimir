# MCP Prometheus Server — Upgrade Guide

A complete guide for upgrading the MCP Prometheus server, from simple Docker version bumps to full Kubernetes rolling upgrades.

## Table of Contents

1. [Version Check](#version-check)
2. [Basic: Upgrade mcp-prometheus Binary Version (Docker)](#basic-upgrade-mcp-prometheus-binary-version-docker)
3. [Basic: Upgrade Docker Base Image](#basic-upgrade-docker-base-image)
4. [Basic: Upgrade Docker Compose Configuration](#basic-upgrade-docker-compose-configuration)
5. [Intermediate: Upgrade with Zero Downtime (Docker)](#intermediate-upgrade-with-zero-downtime-docker)
6. [Intermediate: Upgrade Environment Variables / Configuration](#intermediate-upgrade-environment-variables--configuration)
7. [Intermediate: Upgrade Transport Protocol](#intermediate-upgrade-transport-protocol)
8. [Advanced: Upgrade in Kubernetes / AKS](#advanced-upgrade-in-kubernetes--aks)
   - [Rolling update (default)](#rolling-update-default)
   - [Blue-green deployment](#blue-green-deployment)
   - [Canary deployment](#canary-deployment)
9. [Advanced: Upgrade Across Environments (Dev > Perf > Prod)](#advanced-upgrade-across-environments-dev--perf--prod)
10. [Advanced: Upgrade Kubernetes Manifests](#advanced-upgrade-kubernetes-manifests)
11. [Rollback Procedures](#rollback-procedures)
    - [Docker rollback](#docker-rollback)
    - [Kubernetes rollback](#kubernetes-rollback)
12. [Upgrade Checklist](#upgrade-checklist)
13. [Version Compatibility Matrix](#version-compatibility-matrix)

---

## Version Check

Before upgrading, check your current version:

```bash
# Docker — check running binary version
docker exec mcp-prometheus sh -c 'mcp-prometheus --version' 2>/dev/null || echo "Version flag not supported — check Dockerfile for VERSION arg"

# Check the Dockerfile for the pinned version
grep "ARG VERSION" Dockerfile

# Check the latest available version
curl -s https://api.github.com/repos/giantswarm/mcp-prometheus/releases/latest | grep tag_name

# Check Prometheus build info via MCP tool
curl -s http://localhost:9091/metrics | grep build_info
```

---

## Basic: Upgrade mcp-prometheus Binary Version (Docker)

This is the most common upgrade — updating the `mcp-prometheus` binary to a newer release.

### Step 1: Check available versions

Visit the [releases page](https://github.com/giantswarm/mcp-prometheus/releases) or run:
```bash
curl -s https://api.github.com/repos/giantswarm/mcp-prometheus/releases | grep tag_name | head -10
```

### Step 2: Update the Dockerfile

Edit the `VERSION` argument in `Dockerfile`:

```dockerfile
# Before
ARG VERSION=0.0.59

# After (example)
ARG VERSION=0.0.65
```

### Step 3: Rebuild and restart

```bash
# Rebuild the image (--no-cache ensures the new binary is downloaded)
docker compose build --no-cache

# Restart with the new image
docker compose down && docker compose up -d
```

### Step 4: Verify

```bash
# Check container is healthy
docker compose ps

# Check logs for startup errors
docker compose logs --tail=20 mcp-prometheus

# Test health
curl http://localhost:9091/healthz

# Test SSE endpoint
curl -s --max-time 3 http://localhost:8080/sse

# Verify Prometheus connectivity
docker exec mcp-prometheus sh -c 'wget -qO- $PROMETHEUS_URL/api/v1/status/buildinfo'
```

---

## Basic: Upgrade Docker Base Image

Update the Alpine base image for security patches.

### Step 1: Update the Dockerfile

```dockerfile
# Before
FROM alpine:3.20

# After
FROM alpine:3.21
```

### Step 2: Rebuild

```bash
docker compose build --no-cache
docker compose down && docker compose up -d
```

### Step 3: Verify

```bash
docker compose ps
docker exec mcp-prometheus cat /etc/alpine-release
```

---

## Basic: Upgrade Docker Compose Configuration

When `docker-compose.yml` structure changes (new ports, volumes, networks):

```bash
# Stop the current deployment
docker compose down

# Review changes
git diff docker-compose.yml

# Start with the new configuration
docker compose up -d

# Verify
docker compose ps
```

---

## Intermediate: Upgrade with Zero Downtime (Docker)

For local setups where you want to minimize disruption:

### Option A: Build first, then swap

```bash
# Build the new image while the old one is still running
docker compose build --no-cache

# Quick stop and start (minimizes downtime to a few seconds)
docker compose down && docker compose up -d
```

### Option B: Run new version on a different port

```bash
# Start new version on port 8081
MCP_PORT=8081 METRICS_PORT=9092 docker compose -p mcp-prometheus-new up -d --build

# Test the new version
curl http://localhost:9092/healthz
curl -s --max-time 3 http://localhost:8081/sse

# If good, stop the old version
docker compose down

# Switch the new version to the standard port
docker compose -p mcp-prometheus-new down
docker compose up -d
```

---

## Intermediate: Upgrade Environment Variables / Configuration

When new environment variables are added in a newer version.

### Step 1: Compare with the example

```bash
# Check what's new in .env.example
diff .env .env.example
```

### Step 2: Add new variables to `.env`

```bash
# Add any new variables with their defaults
echo 'NEW_VARIABLE=default_value' >> .env
```

### Step 3: Restart

```bash
docker compose restart
# or for a clean restart:
docker compose down && docker compose up -d
```

### Step 4: Verify new variables are loaded

```bash
docker exec mcp-prometheus env | grep NEW_VARIABLE
```

---

## Intermediate: Upgrade Transport Protocol

The MCP server supports multiple transports. To switch:

### SSE (default) to Streamable HTTP

```bash
# Update .env
TRANSPORT=streamable-http
```

Update `.vscode/mcp.json` to match:
```json
{
  "servers": {
    "mcp-prometheus": {
      "type": "streamable-http",
      "url": "http://localhost:8080/mcp"
    }
  }
}
```

```bash
docker compose down && docker compose up -d
```

### SSE to stdio (for direct process integration)

```bash
TRANSPORT=stdio
```

Note: `stdio` transport doesn't use HTTP — the AI tool communicates directly via stdin/stdout. This is typically used without Docker.

---

## Advanced: Upgrade in Kubernetes / AKS

### Rolling update (default)

The default Kubernetes deployment strategy. Pods are replaced one at a time.

#### Step 1: Update the image

```bash
# Build and push new image to ACR
export ACR_REGISTRY=your-acr-name.azurecr.io
export IMAGE_TAG=v0.0.65

docker build -t $ACR_REGISTRY/mcp-prometheus:$IMAGE_TAG .
docker push $ACR_REGISTRY/mcp-prometheus:$IMAGE_TAG
```

#### Step 2: Deploy to each environment

```bash
# Deploy to dev first
IMAGE_TAG=v0.0.65 ./k8s/deploy.sh dev

# Verify in dev
kubectl get pods -n mcp-prometheus-dev -w

# Then perf
IMAGE_TAG=v0.0.65 ./k8s/deploy.sh perf

# Finally prod
IMAGE_TAG=v0.0.65 ./k8s/deploy.sh prod
```

#### Step 3: Monitor the rollout

```bash
ENV=dev  # or perf, prod
kubectl rollout status deployment/mcp-prometheus -n mcp-prometheus-$ENV --timeout=120s
kubectl get pods -n mcp-prometheus-$ENV
```

### Blue-green deployment

Run old and new versions simultaneously, then switch traffic.

```bash
ENV=prod
NAMESPACE=mcp-prometheus-$ENV

# Deploy new version with a different label
kubectl set image deployment/mcp-prometheus mcp-prometheus=$ACR_REGISTRY/mcp-prometheus:v0.0.65 -n $NAMESPACE

# Watch the rollout
kubectl rollout status deployment/mcp-prometheus -n $NAMESPACE

# If something goes wrong, rollback immediately
kubectl rollout undo deployment/mcp-prometheus -n $NAMESPACE
```

### Canary deployment

Send a small percentage of traffic to the new version.

```bash
ENV=prod
NAMESPACE=mcp-prometheus-$ENV

# Scale up with new image (1 new pod alongside existing ones)
kubectl scale deployment/mcp-prometheus -n $NAMESPACE --replicas=4
kubectl set image deployment/mcp-prometheus mcp-prometheus=$ACR_REGISTRY/mcp-prometheus:v0.0.65 -n $NAMESPACE

# Monitor for errors
kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=mcp-prometheus --tail=50 -f

# If healthy, let the rollout complete
# If not, rollback
kubectl rollout undo deployment/mcp-prometheus -n $NAMESPACE
```

---

## Advanced: Upgrade Across Environments (Dev > Perf > Prod)

Follow this promotion path for safe production upgrades:

### 1. Dev environment

```bash
# Deploy
IMAGE_TAG=v0.0.65 ./k8s/deploy.sh dev

# Validate
kubectl get pods -n mcp-prometheus-dev
curl http://<dev-ingress>/sse
# Run smoke tests — execute a basic query
```

### 2. Perf environment

```bash
# Deploy after dev validation (wait at least 1 hour)
IMAGE_TAG=v0.0.65 ./k8s/deploy.sh perf

# Load test
# Run your standard performance tests against the perf endpoint
```

### 3. Prod environment

```bash
# Deploy after perf validation
IMAGE_TAG=v0.0.65 ./k8s/deploy.sh prod

# Monitor
kubectl get pods -n mcp-prometheus-prod -w
kubectl logs -n mcp-prometheus-prod -l app.kubernetes.io/name=mcp-prometheus -f
```

### Promotion gates

| Gate | Criteria |
|------|----------|
| Dev -> Perf | All 18 MCP tools respond correctly, health check passes |
| Perf -> Prod | No errors under load, latency within SLA, memory stable |
| Prod post-deploy | Monitor for 15 minutes, check error rates and SSE stability |

---

## Advanced: Upgrade Kubernetes Manifests

When upgrading the Kubernetes configuration itself (not just the binary):

### Updating resource limits

Edit the overlay patch for your environment:

```bash
# Example: Update prod resources
# Edit k8s/overlays/prod/deployment-patch.yaml
```

```yaml
# Increase memory limit
resources:
  requests:
    cpu: 500m
    memory: 512Mi
  limits:
    cpu: 2
    memory: 1Gi
```

Apply:
```bash
./k8s/deploy.sh prod
```

### Updating HPA settings

Edit `k8s/overlays/<env>/hpa-patch.yaml`:

```yaml
spec:
  minReplicas: 3
  maxReplicas: 15
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
```

Apply:
```bash
./k8s/deploy.sh prod
```

### Preview changes before applying

Always dry-run first:
```bash
./k8s/deploy.sh prod --dry-run
```

---

## Rollback Procedures

### Docker rollback

```bash
# Option 1: Revert the Dockerfile and rebuild
git checkout HEAD~1 -- Dockerfile
docker compose build --no-cache
docker compose down && docker compose up -d

# Option 2: If you tagged the previous image
docker compose down
docker tag mcp-prometheus:previous mcp-prometheus:latest
docker compose up -d
```

### Kubernetes rollback

```bash
ENV=prod
NAMESPACE=mcp-prometheus-$ENV

# Check rollout history
kubectl rollout history deployment/mcp-prometheus -n $NAMESPACE

# Rollback to the previous version
kubectl rollout undo deployment/mcp-prometheus -n $NAMESPACE

# Rollback to a specific revision
kubectl rollout undo deployment/mcp-prometheus -n $NAMESPACE --to-revision=3

# Verify
kubectl rollout status deployment/mcp-prometheus -n $NAMESPACE
kubectl get pods -n $NAMESPACE
```

### Emergency rollback (prod)

```bash
# Immediate rollback — don't wait
kubectl rollout undo deployment/mcp-prometheus -n mcp-prometheus-prod

# Verify pods are running
kubectl get pods -n mcp-prometheus-prod -w

# Check health
kubectl exec -n mcp-prometheus-prod <pod-name> -- wget -qO- http://localhost:9091/healthz
```

---

## Upgrade Checklist

Use this checklist for every upgrade:

### Before upgrade
- [ ] Note the current version: `grep "ARG VERSION" Dockerfile`
- [ ] Read the release notes for the new version
- [ ] Check for breaking changes or new required environment variables
- [ ] Backup current `.env` and `docker-compose.yml`
- [ ] For Kubernetes: run `./k8s/deploy.sh <env> --dry-run` first

### During upgrade
- [ ] Update `VERSION` in Dockerfile
- [ ] Rebuild with `--no-cache`
- [ ] Deploy to dev first, then perf, then prod
- [ ] Monitor logs during rollout

### After upgrade
- [ ] Health check passes: `curl http://localhost:9091/healthz`
- [ ] SSE endpoint responds: `curl -s --max-time 3 http://localhost:8080/sse`
- [ ] Prometheus connectivity works: `docker exec mcp-prometheus sh -c 'wget -qO- $PROMETHEUS_URL/api/v1/status/buildinfo'`
- [ ] VS Code can connect and query data
- [ ] All 18 MCP tools are listed in VS Code
- [ ] Run a test query: ask "What targets are up?"

---

## Version Compatibility Matrix

| mcp-prometheus version | Prometheus | Mimir | Transport | Notes |
|---|---|---|---|---|
| v0.0.50+ | 2.x, 3.x | 2.x | SSE, stdio | Baseline support |
| v0.0.55+ | 2.x, 3.x | 2.x | SSE, stdio, streamable-http | Added streamable-http |
| v0.0.59 (current) | 2.x, 3.x | 2.x | SSE, stdio, streamable-http | Current pinned version |

**Note:** Check the [upstream releases](https://github.com/giantswarm/mcp-prometheus/releases) for the latest compatibility information. The matrix above is based on the versions tested with this deployment configuration.
