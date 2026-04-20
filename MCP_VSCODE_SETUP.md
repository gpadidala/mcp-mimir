# MCP Mimir Server — VS Code Connection Setup Guide

Complete step-by-step guide to deploy the MCP Mimir Server on AKS and connect it to VS Code (Copilot / Claude) for AI-powered Prometheus/Mimir querying.

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Deploy to AKS](#2-deploy-to-aks)
3. [Verify the Deployment](#3-verify-the-deployment)
4. [Connection URLs by Environment](#4-connection-urls-by-environment)
5. [Connect VS Code to MCP Server](#5-connect-vs-code-to-mcp-server)
6. [Connect Claude Code CLI to MCP Server](#6-connect-claude-code-cli-to-mcp-server)
7. [Connect GitHub Copilot to MCP Server](#7-connect-github-copilot-to-mcp-server)
8. [Test the Connection](#8-test-the-connection)
9. [Available MCP Tools](#9-available-mcp-tools)
10. [Troubleshooting](#10-troubleshooting)

---

## 1. Prerequisites

Before you begin, ensure you have:

- **kubectl** configured and pointing to the correct AKS cluster
- **Azure CLI** (`az`) logged in (for ACR access)
- **VS Code** with one of:
  - [GitHub Copilot](https://marketplace.visualstudio.com/items?itemName=GitHub.copilot) extension
  - [Claude Code](https://marketplace.visualstudio.com/items?itemName=anthropics.claude-code) extension
- Access to the AKS cluster namespace (`sample-dev`, `sample-perf`, or `sample-prod`)

Verify your cluster access:

```bash
# Check current context
kubectl config current-context

# Verify namespace access
kubectl get pods -n sample-dev
```

---

## 2. Deploy to AKS

### Option A: Single-file deploy (recommended for dev)

```bash
# Deploy all resources in one shot
kubectl apply -f k8s/mcp-mimir-aks-dev.yaml
```

### Option B: Kustomize overlays (for any environment)

```bash
# Dev
./k8s/deploy.sh dev

# Perf
./k8s/deploy.sh perf

# Prod
./k8s/deploy.sh prod

# Dry run first (preview without applying)
./k8s/deploy.sh dev --dry-run
```

---

## 3. Verify the Deployment

```bash
# Check pod is running
kubectl get pods -n sample-dev -l app=sample-mcp-mimir
```

Expected output:
```
NAME                               READY   STATUS    RESTARTS   AGE
sample-mcp-mimir-7b8f9c6d4-x2k9p   1/1     Running   0          30s
```

```bash
# Check service
kubectl get svc -n sample-dev -l app=sample-mcp-mimir
```

Expected output:
```
NAME              TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)              AGE
sample-mcp-mimir   ClusterIP   10.0.xxx.xxx   <none>        8000/TCP,9090/TCP   30s
```

```bash
# Check VirtualService (Istio routing)
kubectl get virtualservice -n sample-dev sample-mcp-mimir-vs
```

```bash
# Check pod logs
kubectl logs -n sample-dev -l app=sample-mcp-mimir -f
```

```bash
# Test health endpoint via port-forward
kubectl port-forward -n sample-dev svc/sample-mcp-mimir 8000:8000 &
curl http://localhost:8000/healthz
```

Expected: `OK` or `{"status":"ok"}`

```bash
# Test SSE endpoint
curl -N http://localhost:8000/sse
```

Expected: SSE stream opens and stays connected (press Ctrl+C to stop).

---

## 4. Connection URLs by Environment

| Environment | Istio External URL | Internal Cluster URL |
|-------------|-------------------|---------------------|
| **Dev** | `https://sample-metrics-perf-01.albertsons.com/mcp-mimir/sse` | `http://sample-mcp-mimir.sample-dev.svc.cluster.local:8000/sse` |
| **Perf** | `https://sample-metrics-perf-01.albertsons.com/mcp-mimir/sse` | `http://sample-mcp-mimir.sample-perf.svc.cluster.local:8000/sse` |
| **Prod** | `https://sample-metrics-prod-01.albertsons.com/mcp-mimir/sse` | `http://sample-mcp-mimir.sample-prod.svc.cluster.local:8000/sse` |
| **Local (port-forward)** | `http://localhost:8000/sse` | — |

**For VS Code connections, use the Istio external URL** (or `localhost` if port-forwarding).

---

## 5. Connect VS Code to MCP Server

### Step 1: Open VS Code Settings

Press `Cmd+Shift+P` (Mac) or `Ctrl+Shift+P` (Windows/Linux) and type:

```
Preferences: Open User Settings (JSON)
```

### Step 2: Add MCP Server Configuration

Add the following to your `settings.json`:

```json
{
  "mcp.servers": {
    "mcp-mimir": {
      "type": "sse",
      "url": "https://sample-metrics-perf-01.albertsons.com/mcp-mimir/sse"
    }
  }
}
```

**Or for local port-forward testing:**

```json
{
  "mcp.servers": {
    "mcp-mimir": {
      "type": "sse",
      "url": "http://localhost:8000/sse"
    }
  }
}
```

### Step 3: Alternative — Workspace-level `.vscode/mcp.json`

Create or update `.vscode/mcp.json` in your project root:

```json
{
  "inputs": [
    {
      "id": "mcp-mimir-url",
      "type": "promptString",
      "description": "MCP Mimir SSE endpoint URL",
      "default": "https://sample-metrics-perf-01.albertsons.com/mcp-mimir/sse"
    },
    {
      "id": "prometheus-org-id",
      "type": "promptString",
      "description": "Prometheus/Mimir Org ID (X-Scope-OrgID header)",
      "default": "aks-tru-clusters"
    }
  ],
  "servers": {
    "mcp-mimir": {
      "type": "sse",
      "url": "${input:mcp-mimir-url}",
      "headers": {
        "X-Scope-OrgID": "${input:prometheus-org-id}"
      }
    }
  }
}
```

This prompts you for the URL and org ID each time VS Code starts, making it easy to switch environments.

### Step 4: Reload VS Code

Press `Cmd+Shift+P` → `Developer: Reload Window`

You should see the MCP server icon in the status bar. Click it to verify the connection is active.

---

## 6. Connect Claude Code CLI to MCP Server

### Option A: Project-level config

Create `.mcp.json` in your project root:

```json
{
  "mcpServers": {
    "mcp-mimir": {
      "type": "sse",
      "url": "https://sample-metrics-perf-01.albertsons.com/mcp-mimir/sse",
      "headers": {
        "X-Scope-OrgID": "aks-tru-clusters"
      }
    }
  }
}
```

### Option B: Global config

Add to `~/.claude/settings.json`:

```json
{
  "mcpServers": {
    "mcp-mimir": {
      "type": "sse",
      "url": "https://sample-metrics-perf-01.albertsons.com/mcp-mimir/sse",
      "headers": {
        "X-Scope-OrgID": "aks-tru-clusters"
      }
    }
  }
}
```

### Option C: CLI flag

```bash
claude --mcp-server "mcp-mimir=sse:https://sample-metrics-perf-01.albertsons.com/mcp-mimir/sse"
```

---

## 7. Connect GitHub Copilot to MCP Server

### Step 1: Enable MCP in Copilot

In VS Code settings (`settings.json`), ensure MCP is enabled:

```json
{
  "github.copilot.chat.mcp.enabled": true
}
```

### Step 2: Add Server in `.vscode/mcp.json`

```json
{
  "servers": {
    "mcp-mimir": {
      "type": "sse",
      "url": "https://sample-metrics-perf-01.albertsons.com/mcp-mimir/sse"
    }
  }
}
```

### Step 3: Use in Copilot Chat

Open Copilot Chat (`Cmd+Shift+I`) and ask:

```
@mcp-mimir What is the current CPU usage across all namespaces?
```

Copilot will use the MCP tools to query Prometheus/Mimir and return the results.

---

## 8. Test the Connection

Once connected, try these prompts in your AI assistant:

### Basic health check
```
Can you check if the Prometheus/Mimir connection is working?
```

### Query metrics
```
Show me the CPU usage for all pods in the sample-dev namespace over the last 1 hour.
```

### Infrastructure overview
```
Give me an overview of node resource utilization across the cluster.
```

### Investigate an issue
```
The checkout service seems slow. Can you check its p99 latency and error rate
over the last 30 minutes?
```

### PromQL query
```
Run this PromQL query: sum(rate(http_requests_total[5m])) by (service)
```

---

## 9. Available MCP Tools

The MCP Mimir Server exposes these tools to AI assistants:

| Tool | Description |
|------|-------------|
| `prometheus_query` | Execute an instant PromQL query |
| `prometheus_query_range` | Execute a range PromQL query over a time window |
| `prometheus_series` | Find time series matching label selectors |
| `prometheus_labels` | List all label names |
| `prometheus_label_values` | List values for a specific label |
| `prometheus_targets` | List active Prometheus scrape targets |
| `prometheus_alerts` | List active alerts |
| `prometheus_rules` | List recording and alerting rules |
| `prometheus_metadata` | Get metric metadata (type, help, unit) |
| `prometheus_status_config` | Get Prometheus configuration |
| `prometheus_status_flags` | Get Prometheus command-line flags |
| `prometheus_status_runtime` | Get runtime information |
| `prometheus_status_build` | Get build information |
| `prometheus_status_tsdb` | Get TSDB statistics |
| `prometheus_status_wal_replay` | Get WAL replay status |
| `prometheus_exemplars` | Query exemplars |
| `prometheus_target_metadata` | Get metadata for specific targets |

---

## 10. Troubleshooting

### "Connection refused" or "Cannot connect to MCP server"

**Check the pod is running:**
```bash
kubectl get pods -n sample-dev -l app=sample-mcp-mimir
```

**Check pod logs for errors:**
```bash
kubectl logs -n sample-dev -l app=sample-mcp-mimir --tail=50
```

**Test with port-forward:**
```bash
kubectl port-forward -n sample-dev svc/sample-mcp-mimir 8000:8000
curl http://localhost:8000/healthz
curl -N http://localhost:8000/sse
```

### "SSE connection drops after a few seconds"

This is usually an Istio/ingress timeout issue. The VirtualService is configured to handle long-lived SSE connections, but check:

```bash
# Verify VirtualService is applied
kubectl get virtualservice -n sample-dev sample-mcp-mimir-vs -o yaml
```

Ensure the `/message` route exists — VS Code posts SSE callbacks to this path.

### "No data returned from queries"

**Check the ConfigMap has the correct Prometheus URL:**
```bash
kubectl get configmap mcp-mimir-config -n sample-dev -o yaml
```

**Verify Prometheus/Mimir is reachable from the pod:**
```bash
kubectl exec -n sample-dev -it deploy/sample-mcp-mimir -- \
  wget -qO- "https://sample-metrics-perf-01.albertsons.com/prometheus/api/v1/query?query=up"
```

### "X-Scope-OrgID error" or "no org ID"

If your Mimir instance requires multi-tenancy, ensure the org ID header is set:

- In `.vscode/mcp.json`, add `"headers": { "X-Scope-OrgID": "aks-tru-clusters" }`
- Or in the ConfigMap: `PROMETHEUS_ORGID: "aks-tru-clusters"`

### Pod is CrashLoopBackOff

```bash
# Check events
kubectl describe pod -n sample-dev -l app=sample-mcp-mimir

# Check previous logs
kubectl logs -n sample-dev -l app=sample-mcp-mimir --previous
```

Common causes:
- Wrong `PROMETHEUS_URL` in ConfigMap
- Container can't write to filesystem (ensure `/tmp` volume mount exists)
- Port conflict (ensure `HTTP_ADDR` and `METRICS_ADDR` match container ports)

### ConfigMap changes not taking effect

ConfigMap changes require a pod restart:
```bash
kubectl rollout restart deployment/sample-mcp-mimir -n sample-dev
```

---

## Quick Reference

```bash
# ── Deploy ──
kubectl apply -f k8s/mcp-mimir-aks-dev.yaml

# ── Check status ──
kubectl get pods -n sample-dev -l app=sample-mcp-mimir

# ── View logs ──
kubectl logs -n sample-dev -l app=sample-mcp-mimir -f

# ── Port forward for local testing ──
kubectl port-forward -n sample-dev svc/sample-mcp-mimir 8000:8000

# ── Test health ──
curl http://localhost:8000/healthz

# ── Test SSE ──
curl -N http://localhost:8000/sse

# ── Update config ──
kubectl edit configmap mcp-mimir-config -n sample-dev
kubectl rollout restart deployment/sample-mcp-mimir -n sample-dev

# ── Scale ──
kubectl scale deployment/sample-mcp-mimir -n sample-dev --replicas=2

# ── Delete ──
kubectl delete -f k8s/mcp-mimir-aks-dev.yaml
```
