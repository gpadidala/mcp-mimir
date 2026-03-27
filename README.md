# MCP Mimir — MCP Prometheus Server for AI-Powered Observability

A Dockerized deployment of [**mcp-prometheus**](https://github.com/giantswarm/mcp-prometheus) that connects AI assistants (Claude, Copilot, etc.) to Prometheus and Grafana Mimir via the [Model Context Protocol (MCP)](https://modelcontextprotocol.io/). Includes production-ready Kubernetes manifests for AKS with Kustomize overlays for dev, perf, and prod environments.

## Architecture

```
                         +--------------------------+
                         |      VS Code / IDE       |
                         |  (Claude / Copilot / AI) |
                         +------------+-------------+
                                      |
                                      | MCP (SSE transport)
                                      | http://localhost:8080/sse
                                      |
                         +------------v-------------+
                         |   mcp-prometheus server   |
                         |   (Docker container)      |
                         |                           |
                         |   :8080  MCP SSE endpoint |
                         |   :9091  /healthz /metrics|
                         +---+-----------+------+----+
                             |           |      |
                     --------+-----------+------+--------
                     |                   |               |
              +------v------+   +-------v------+  +-----v-------+
              | Prometheus   |  | Grafana Mimir |  |   Cortex    |
              | :9090        |  | (multi-tenant)|  | (multi-org) |
              +--------------+  +--------------+   +-------------+
                                       |
                              X-Scope-OrgID header
                              (per-tenant queries)
```

### How It Works

1. **AI assistant** (in VS Code) connects to the MCP server via **Server-Sent Events (SSE)** on port 8080
2. **MCP server** exposes **18 read-only tools** for querying Prometheus/Mimir
3. AI calls tools like `execute_query`, `get_targets`, `list_label_values` etc.
4. MCP server forwards requests to **Prometheus/Mimir** using the configured URL and optional `X-Scope-OrgID` header for multi-tenancy
5. Results are returned to the AI for analysis, summarization, or troubleshooting

### AKS Deployment Architecture

```
                        Azure Kubernetes Service (AKS)
  +----------------------------------------------------------------------+
  |                                                                      |
  |  +-------------------+  +--------------------+  +-----------------+  |
  |  | mcp-prometheus-dev|  | mcp-prometheus-perf|  | mcp-prometheus- |  |
  |  | Namespace         |  | Namespace          |  | prod Namespace  |  |
  |  |                   |  |                    |  |                 |  |
  |  | 1 replica         |  | 2 replicas         |  | 3 replicas (HA) |  |
  |  | 50m/64Mi CPU/Mem  |  | 250m/256Mi CPU/Mem |  | 500m/512Mi      |  |
  |  | HPA: 1-2          |  | HPA: 2-8           |  | HPA: 3-10       |  |
  |  |                   |  |                    |  | + PDB            |  |
  |  | -> mimir-dev      |  | -> mimir-perf      |  | + NetworkPolicy  |  |
  |  |    OrgID: dev-     |  |    OrgID: perf-    |  | + TLS            |  |
  |  |    tenant          |  |    tenant          |  | -> mimir-prod    |  |
  |  +-------------------+  +--------------------+  | OrgID: prod-     |  |
  |                                                  |    tenant        |  |
  |                                                  +-----------------+  |
  |                                                                      |
  |  +---------------------------+                                       |
  |  | NGINX Ingress Controller  |  SSE-optimized (proxy_buffering off)  |
  |  +---------------------------+                                       |
  +----------------------------------------------------------------------+
```

## Source Code

| Component | Source | License |
|-----------|--------|---------|
| **mcp-prometheus** (binary) | [giantswarm/mcp-prometheus](https://github.com/giantswarm/mcp-prometheus) | Apache 2.0 |
| **Binary version** | [v0.0.59](https://github.com/giantswarm/mcp-prometheus/releases/tag/v0.0.59) | |
| **MCP Protocol** | [modelcontextprotocol.io](https://modelcontextprotocol.io/) | MIT |
| **This repo** (Dockerfile, K8s, config) | [gpadidala/mcp-mimir](https://github.com/gpadidala/mcp-mimir) | |

## Repository Structure

```
mcp-mimir/
  Dockerfile                 # Containerized mcp-prometheus with configurable env vars
  docker-compose.yml         # Local development (+ multi-org template)
  .env.example               # All configurable environment variables
  .vscode/mcp.json           # VS Code MCP server config with input prompts
  USER_GUIDE.md              # Full reference for all 18 tools + query examples
  README.md                  # This file
  k8s/
    deploy.sh                # One-command deploy script
    base/                    # Shared Kubernetes manifests
      kustomization.yaml
      namespace.yaml
      serviceaccount.yaml
      deployment.yaml        # Pod spec, probes, envFrom ConfigMap + Secret
      service.yaml           # ClusterIP: 8080 (MCP) + 9091 (metrics)
      ingress.yaml           # NGINX with SSE-optimized proxy settings
      hpa.yaml               # CPU/Memory-based autoscaling
      secret.yaml            # Auth credentials (username/password/token)
    overlays/
      dev/                   # Dev: 1 replica, minimal resources, debug
        kustomization.yaml
        deployment-patch.yaml
        ingress-patch.yaml
        hpa-patch.yaml
      perf/                  # Perf: 2 replicas, higher limits, topology spread
        kustomization.yaml
        deployment-patch.yaml
        ingress-patch.yaml
        hpa-patch.yaml
      prod/                  # Prod: 3 replicas, HA, TLS, rate-limiting
        kustomization.yaml
        deployment-patch.yaml
        ingress-patch.yaml
        hpa-patch.yaml
        pdb.yaml             # PodDisruptionBudget (minAvailable: 2)
        networkpolicy.yaml   # Ingress/egress lockdown
```

## Quick Start

### Prerequisites

- Docker Desktop
- Prometheus running at `http://localhost:9090` (or any Prometheus/Mimir endpoint)

### Local (Docker)

```bash
# Build and start
docker compose up -d --build

# Verify
curl http://localhost:9091/healthz       # ok
curl -s --max-time 3 http://localhost:8080/sse  # SSE stream

# With a specific org/tenant
PROMETHEUS_ORGID=my-tenant docker compose up -d

# Stop
docker compose down
```

### AKS (Kubernetes)

```bash
# Preview manifests
./k8s/deploy.sh dev --dry-run

# Deploy to environment
./k8s/deploy.sh dev
./k8s/deploy.sh perf
./k8s/deploy.sh prod

# Delete
./k8s/deploy.sh dev --delete
```

### VS Code Integration

The `.vscode/mcp.json` is included. When VS Code connects, it prompts for:
- **SSE endpoint URL** (default: `http://localhost:8080/sse`)
- **Org ID** for multi-tenancy (optional)

The MCP server will appear in the VS Code MCP panel with all 18 tools.

## Configuration

All values are configurable at runtime via environment variables:

| Variable | Description | Default |
|----------|-------------|---------|
| `PROMETHEUS_URL` | Prometheus/Mimir endpoint | `http://host.docker.internal:9090` |
| `PROMETHEUS_ORGID` | Default org/tenant ID (sent as `X-Scope-OrgID`) | _(empty)_ |
| `PROMETHEUS_USERNAME` | Basic auth username | _(empty)_ |
| `PROMETHEUS_PASSWORD` | Basic auth password | _(empty)_ |
| `PROMETHEUS_TOKEN` | Bearer token | _(empty)_ |
| `TRANSPORT` | MCP transport: `sse`, `stdio`, `streamable-http` | `sse` |
| `HTTP_ADDR` | MCP server listen address | `:8080` |
| `METRICS_ADDR` | Health/metrics server address | `:9091` |

Set via `.env` file, shell environment, docker-compose, or Kubernetes ConfigMap.

## Available MCP Tools (18)

### Querying
| Tool | Description |
|------|-------------|
| `execute_query` | PromQL instant query |
| `execute_range_query` | PromQL range query (start/end/step) |
| `query_exemplars` | Query exemplars for tracing |

### Discovery
| Tool | Description |
|------|-------------|
| `find_series` | Find series by label matchers |
| `list_label_names` | All available label names |
| `list_label_values` | Values for a specific label |
| `get_metric_metadata` | Metric type, help, unit |
| `get_targets_metadata` | Per-target metric metadata |

### Infrastructure
| Tool | Description |
|------|-------------|
| `check_ready` | Is Prometheus/Mimir ready? |
| `get_targets` | Scrape target health and status |
| `get_alerts` | Active/firing alerts |
| `get_alertmanagers` | AlertManager discovery |
| `get_rules` | Recording and alerting rules |

### Server Info
| Tool | Description |
|------|-------------|
| `get_build_info` | Version, revision, Go version |
| `get_config` | Current YAML configuration |
| `get_flags` | Runtime startup flags |
| `get_runtime_info` | Goroutines, GOGC, retention |
| `get_tsdb_stats` | Series count, cardinality |

Every tool accepts optional `org_id` and `prometheus_url` parameters for per-request overrides.

## Environment Comparison (AKS)

| | Dev | Perf | Prod |
|---|-----|------|------|
| **Namespace** | `mcp-prometheus-dev` | `mcp-prometheus-perf` | `mcp-prometheus-prod` |
| **Replicas** | 1 | 2 | 3 |
| **HPA range** | 1-2 | 2-8 | 3-10 |
| **CPU req / limit** | 50m / 250m | 250m / 1 core | 500m / 2 cores |
| **Memory req / limit** | 64Mi / 128Mi | 256Mi / 512Mi | 512Mi / 1Gi |
| **Org ID** | `dev-tenant` | `perf-tenant` | `prod-tenant` |
| **PodDisruptionBudget** | -- | -- | minAvailable: 2 |
| **NetworkPolicy** | -- | -- | Ingress + Egress locked |
| **TLS** | -- | -- | cert-manager |
| **Rate limiting** | -- | -- | 50 rps |
| **Pod anti-affinity** | -- | hostname | zone + hostname |
| **HPA scale-down** | default | default | 5min stabilization |

## Multi-Tenancy (Mimir / Cortex)

Three ways to set the org/tenant ID:

```bash
# 1. Environment variable (global default)
PROMETHEUS_ORGID=my-tenant docker compose up -d

# 2. Per tool call (runtime override via AI)
{ "name": "execute_query", "arguments": { "query": "up", "org_id": "tenant-abc" } }

# 3. Multiple MCP servers (one per org) — uncomment in docker-compose.yml
# mcp-prometheus-org1 on :8081 with PROMETHEUS_ORGID=org-1
# mcp-prometheus-org2 on :8082 with PROMETHEUS_ORGID=org-2
```

## Example Queries

```json
// Check which targets are up
{ "name": "execute_query", "arguments": { "query": "up" } }

// CPU usage percentage (node exporter)
{ "name": "execute_query", "arguments": {
    "query": "100 - (avg by (instance) (rate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100)"
} }

// Memory trend over last hour
{ "name": "execute_range_query", "arguments": {
    "query": "process_resident_memory_bytes / 1024 / 1024",
    "start": "2026-03-26T22:00:00Z",
    "end": "2026-03-26T23:00:00Z",
    "step": "5m"
} }

// Discover all metric names
{ "name": "list_label_values", "arguments": { "label": "__name__", "limit": "50" } }

// P99 latency
{ "name": "execute_query", "arguments": {
    "query": "histogram_quantile(0.99, rate(prometheus_http_request_duration_seconds_bucket[5m]))"
} }
```

See [USER_GUIDE.md](USER_GUIDE.md) for the complete reference with 40+ query examples across all 18 tools.

## Ports

| Port | Protocol | Purpose |
|------|----------|---------|
| 8080 | HTTP | MCP SSE transport (`/sse`, `/message`) |
| 9091 | HTTP | Observability (`/healthz`, `/readyz`, `/metrics`) |

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Container restarting | Check `docker logs mcp-prometheus` -- needs `serve --transport sse` |
| Can't reach Prometheus | Use `host.docker.internal` in Docker, not `localhost` |
| SSE stream drops | Normal during container restarts; VS Code auto-reconnects |
| 405 on connect | Expected -- VS Code tries streamable-http first, falls back to SSE |
| Port conflict | Change `MCP_PORT` / `METRICS_PORT` in `.env` |

## License

This deployment configuration is provided as-is. The `mcp-prometheus` binary is developed by [Giant Swarm](https://github.com/giantswarm/mcp-prometheus) under the Apache 2.0 license.
