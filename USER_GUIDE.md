# MCP Prometheus Server - User Guide

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Setup & Installation](#setup--installation)
4. [VS Code Integration](#vs-code-integration)
5. [All 18 MCP Tools Reference](#all-18-mcp-tools-reference)
6. [Query Examples by Category](#query-examples-by-category)
7. [Multi-Tenancy & Org Support](#multi-tenancy--org-support)
8. [Troubleshooting](#troubleshooting)
9. [Advanced Examples](#advanced-examples)
   - [SRE Golden Signals](#1-sre-golden-signals) (latency, traffic, errors, saturation)
   - [SLO & Error Budget](#2-slo--error-budget-queries)
   - [Capacity Planning & Prediction](#3-capacity-planning--prediction)
   - [System Resource Deep Dive](#4-system-resource-deep-dive) (CPU, memory, disk, network)
   - [Garbage Collection & Go Runtime](#5-garbage-collection--go-runtime)
   - [Prometheus Self-Monitoring](#6-prometheus-self-monitoring)
   - [Cardinality & TSDB Management](#7-cardinality--tsdb-management)
   - [Advanced PromQL Techniques](#8-advanced-promql-techniques) (subqueries, irate, label manipulation, absent)
   - [Multi-Tenant / Multi-Org Workflows](#9-multi-tenant--multi-org-workflows)
   - [Incident Response Playbook](#10-incident-response-playbook-queries)
   - [Combined Multi-Tool Workflows](#11-combined-multi-tool-workflows)
   - [Asking AI Natural Language Questions](#12-asking-ai-natural-language-questions)

---

## Overview

MCP Prometheus is a Model Context Protocol (MCP) server that provides AI assistants (Claude, Copilot, etc.) with direct access to your Prometheus/Mimir metrics. It exposes 18 read-only tools for querying, discovering, and analyzing metrics data.

**What you can do:**
- Execute PromQL instant and range queries
- Discover metrics, labels, and series
- Inspect targets, alerts, rules, and configuration
- Get TSDB cardinality statistics
- Query exemplars for distributed tracing
- All with multi-tenant (org) support for Mimir/Cortex

---

## Architecture

```
+------------------+       +----------------------+       +------------------+
|                  |  MCP  |                      | HTTP  |                  |
|  VS Code / AI   |<----->|  mcp-prometheus       |<----->|  Prometheus      |
|  (Claude/Copilot)|  SSE  |  (Docker container)  |       |  localhost:9090  |
|                  |       |  localhost:8080       |       |                  |
+------------------+       +----------------------+       +------------------+
                              |                  |
                              | Health: :9091    |
                              | /healthz /readyz |
                              +------------------+
```

**Ports:**
| Port | Purpose |
|------|---------|
| 8080 | MCP SSE transport (`/sse` and `/message` endpoints) |
| 9091 | Observability (`/healthz`, `/readyz`, `/metrics`) |
| 9090 | Your Prometheus server (external) |

---

## Setup & Installation

### Prerequisites
- Docker Desktop installed and running
- Prometheus running at `http://localhost:9090`

### Quick Start

```bash
# Clone or navigate to the project
cd /path/to/mcp-mimir

# Build and start
docker compose up -d --build

# Verify
curl http://localhost:9091/healthz    # Should return: ok
curl -s --max-time 3 http://localhost:8080/sse  # Should return SSE event
```

### Manual Docker Commands

```bash
# Build the image
docker build -t mcp-prometheus:latest .

# Run the container
docker run -d --name mcp-prometheus \
  -p 8080:8080 -p 9091:9091 \
  -e PROMETHEUS_URL=http://host.docker.internal:9090 \
  --add-host=host.docker.internal:host-gateway \
  mcp-prometheus:latest

# Check logs
docker logs -f mcp-prometheus

# Stop
docker compose down
```

### Push to Local Docker Registry (Optional)

```bash
# Start a local registry if you don't have one
docker run -d -p 5000:5000 --name registry registry:2

# Tag and push
docker tag mcp-prometheus:latest localhost:5000/mcp-prometheus:latest
docker push localhost:5000/mcp-prometheus:latest
```

---

## VS Code Integration

### Option 1: Project-level config (`.vscode/mcp.json`)

```json
{
  "servers": {
    "mcp-prometheus": {
      "type": "sse",
      "url": "http://localhost:8080/sse",
      "headers": {}
    }
  }
}
```

### Option 2: User-level settings (`settings.json`)

```json
{
  "mcp": {
    "servers": {
      "mcp-prometheus": {
        "type": "sse",
        "url": "http://localhost:8080/sse"
      }
    }
  }
}
```

### Option 3: Claude Code (`claude_desktop_config.json` or Claude Code settings)

```json
{
  "mcpServers": {
    "mcp-prometheus": {
      "url": "http://localhost:8080/sse"
    }
  }
}
```

After configuring, the MCP panel in VS Code will show **mcp-prometheus** with all 18 tools available.

---

## All 18 MCP Tools Reference

### Tool 1: `check_ready`
**Check whether the Prometheus/Mimir server is ready to serve traffic.**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `prometheus_url` | string | No | Override Prometheus server URL |
| `org_id` | string | No | Organization ID for multi-tenant setups |

**Example:**
```json
{ "name": "check_ready", "arguments": {} }
```
**Sample Output:** `Prometheus is ready (HTTP 200): Prometheus Server is Ready.`

---

### Tool 2: `execute_query`
**Execute a PromQL instant query against Prometheus.**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `query` | string | **Yes** | PromQL query string |
| `time` | string | No | RFC3339 or Unix timestamp (default: now) |
| `timeout` | string | No | Query timeout (e.g., `30s`, `1m`, `5m`) |
| `limit` | string | No | Maximum number of returned entries |
| `lookback_delta` | string | No | Query lookback delta (e.g., `5m`) |
| `stats` | string | No | Include query statistics: `all` |
| `unlimited` | string | No | Set to `true` for unlimited output |
| `prometheus_url` | string | No | Override Prometheus URL |
| `org_id` | string | No | Organization ID |

**Examples:**

```json
// Basic: Check which targets are up
{ "name": "execute_query", "arguments": { "query": "up" } }

// Rate: HTTP request rate over 5 minutes
{ "name": "execute_query", "arguments": { "query": "rate(prometheus_http_requests_total[5m])" } }

// Aggregation: Sum request rate by job
{ "name": "execute_query", "arguments": { "query": "sum by (job) (rate(prometheus_http_requests_total[5m]))" } }

// Top-K: Top 5 HTTP endpoints by request count
{ "name": "execute_query", "arguments": { "query": "topk(5, prometheus_http_requests_total)" } }

// Histogram: P99 latency
{ "name": "execute_query", "arguments": { "query": "histogram_quantile(0.99, rate(prometheus_http_request_duration_seconds_bucket[5m]))" } }

// Math: Memory usage in MB
{ "name": "execute_query", "arguments": { "query": "process_resident_memory_bytes / 1024 / 1024" } }

// With stats
{ "name": "execute_query", "arguments": { "query": "up", "stats": "all" } }

// Time travel: Query at a specific past time
{ "name": "execute_query", "arguments": { "query": "up", "time": "2026-03-26T22:00:00Z" } }

// With limit
{ "name": "execute_query", "arguments": { "query": "prometheus_http_requests_total", "limit": "3" } }

// Absent: Check if a metric is missing
{ "name": "execute_query", "arguments": { "query": "absent(nonexistent_metric)" } }

// Label replace: Extract hostname from instance
{ "name": "execute_query", "arguments": { "query": "label_replace(up, \"host\", \"$1\", \"instance\", \"(.*):(.*)\") " } }

// Comparison: Processes using more than 1MB
{ "name": "execute_query", "arguments": { "query": "process_resident_memory_bytes > 1000000" } }

// Node CPU usage percentage
{ "name": "execute_query", "arguments": { "query": "100 - (avg by (instance) (rate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100)" } }

// Disk space percentage available
{ "name": "execute_query", "arguments": { "query": "node_filesystem_avail_bytes{mountpoint=\"/\"} / node_filesystem_size_bytes{mountpoint=\"/\"} * 100" } }
```

---

### Tool 3: `execute_range_query`
**Execute a PromQL range query with start time, end time, and step interval.**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `query` | string | **Yes** | PromQL query string |
| `start` | string | **Yes** | Start time (RFC3339 or Unix timestamp) |
| `end` | string | **Yes** | End time (RFC3339 or Unix timestamp) |
| `step` | string | **Yes** | Resolution step (e.g., `15s`, `1m`, `1h`) |
| `timeout` | string | No | Query timeout |
| `limit` | string | No | Max returned entries |
| `lookback_delta` | string | No | Lookback delta |
| `stats` | string | No | Include statistics |
| `unlimited` | string | No | Unlimited output |
| `prometheus_url` | string | No | Override URL |
| `org_id` | string | No | Organization ID |

**Examples:**

```json
// Uptime over last hour, sampled every 15 minutes
{
  "name": "execute_range_query",
  "arguments": {
    "query": "up",
    "start": "2026-03-26T22:00:00Z",
    "end": "2026-03-26T23:00:00Z",
    "step": "15m"
  }
}

// CPU rate trend over last hour
{
  "name": "execute_range_query",
  "arguments": {
    "query": "rate(process_cpu_seconds_total[5m])",
    "start": "2026-03-26T22:00:00Z",
    "end": "2026-03-26T23:00:00Z",
    "step": "5m"
  }
}

// Memory trend in MB over last hour
{
  "name": "execute_range_query",
  "arguments": {
    "query": "process_resident_memory_bytes / 1024 / 1024",
    "start": "2026-03-26T22:00:00Z",
    "end": "2026-03-26T23:00:00Z",
    "step": "10m"
  }
}

// HTTP error rate over 24 hours
{
  "name": "execute_range_query",
  "arguments": {
    "query": "sum(rate(prometheus_http_requests_total{code=~\"5..\"}[5m]))",
    "start": "2026-03-25T23:00:00Z",
    "end": "2026-03-26T23:00:00Z",
    "step": "1h"
  }
}
```

---

### Tool 4: `find_series`
**Find series by label matchers.**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `matches` | array | **Yes** | Array of label matchers |
| `start_time` | string | No | Start time (RFC3339) |
| `end_time` | string | No | End time (RFC3339) |
| `limit` | string | No | Max series to return |
| `prometheus_url` | string | No | Override URL |
| `org_id` | string | No | Organization ID |

**Examples:**

```json
// Find all series for the prometheus job
{ "name": "find_series", "arguments": { "matches": ["{job=\"prometheus\"}"], "limit": "10" } }

// Find series matching a regex pattern
{ "name": "find_series", "arguments": { "matches": ["{__name__=~\"node_cpu.*\"}"], "limit": "10" } }

// Find series with multiple matchers
{ "name": "find_series", "arguments": { "matches": ["{job=\"node\"}", "{__name__=~\"process_.*\"}"], "limit": "5" } }

// Find series within a time window
{
  "name": "find_series",
  "arguments": {
    "matches": ["{job=\"prometheus\"}"],
    "start_time": "2026-03-26T22:00:00Z",
    "end_time": "2026-03-26T23:00:00Z",
    "limit": "5"
  }
}
```

---

### Tool 5: `get_alertmanagers`
**Get AlertManager discovery information.**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `prometheus_url` | string | No | Override URL |
| `org_id` | string | No | Organization ID |

```json
{ "name": "get_alertmanagers", "arguments": {} }
```
**Sample Output:** Shows active and dropped AlertManager instances.

---

### Tool 6: `get_alerts`
**Get active alerts.**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `prometheus_url` | string | No | Override URL |
| `org_id` | string | No | Organization ID |

```json
{ "name": "get_alerts", "arguments": {} }
```
**Sample Output:** `Active Alerts: {Alerts:[]}` (or list of firing alerts)

---

### Tool 7: `get_build_info`
**Get build information about the Prometheus server.**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `prometheus_url` | string | No | Override URL |
| `org_id` | string | No | Organization ID |

```json
{ "name": "get_build_info", "arguments": {} }
```
**Sample Output:** `{Version:3.8.0 Revision:non-git Branch:non-git BuildUser:reproducible@reproducible BuildDate:20251202-08:53:55 GoVersion:go1.25.4}`

---

### Tool 8: `get_config`
**Get the current Prometheus configuration (scrape configs, global settings, etc.).**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `prometheus_url` | string | No | Override URL |
| `org_id` | string | No | Organization ID |

```json
{ "name": "get_config", "arguments": {} }
```
**Sample Output:** Full YAML configuration including `global`, `scrape_configs`, `runtime` settings.

---

### Tool 9: `get_flags`
**Get runtime flags that Prometheus was launched with.**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `prometheus_url` | string | No | Override URL |
| `org_id` | string | No | Organization ID |

```json
{ "name": "get_flags", "arguments": {} }
```
**Sample Output:** All Prometheus startup flags (storage paths, retention, query limits, etc.)

---

### Tool 10: `get_metric_metadata`
**Get metadata (type, help text, unit) for a specific metric.**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `metric` | string | **Yes** | Metric name |
| `limit` | string | No | Max metadata entries |
| `prometheus_url` | string | No | Override URL |
| `org_id` | string | No | Organization ID |

**Examples:**

```json
// Get metadata for HTTP requests counter
{ "name": "get_metric_metadata", "arguments": { "metric": "prometheus_http_requests_total" } }
// Output: type=counter, help="Counter of HTTP requests."

// Get metadata for CPU metric
{ "name": "get_metric_metadata", "arguments": { "metric": "process_cpu_seconds_total" } }
// Output: type=counter, help="Total user and system CPU time spent in seconds."

// Get metadata for Go GC metric
{ "name": "get_metric_metadata", "arguments": { "metric": "go_gc_duration_seconds" } }

// Get metadata for node exporter metric
{ "name": "get_metric_metadata", "arguments": { "metric": "node_cpu_seconds_total" } }
```

---

### Tool 11: `get_rules`
**Get recording and alerting rules.**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `prometheus_url` | string | No | Override URL |
| `org_id` | string | No | Organization ID |

```json
{ "name": "get_rules", "arguments": {} }
```
**Sample Output:** List of rule groups with recording rules and alerting rules.

---

### Tool 12: `get_runtime_info`
**Get runtime information about the Prometheus server.**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `prometheus_url` | string | No | Override URL |
| `org_id` | string | No | Organization ID |

```json
{ "name": "get_runtime_info", "arguments": {} }
```
**Sample Output:** `{StartTime:..., CWD:/, ReloadConfigSuccess:true, GoroutineCount:36, GOMAXPROCS:8, GOGC:75, StorageRetention:15d}`

---

### Tool 13: `get_targets`
**Get information about all scrape targets.**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `prometheus_url` | string | No | Override URL |
| `org_id` | string | No | Organization ID |

```json
{ "name": "get_targets", "arguments": {} }
```
**Sample Output:** Active targets with health status, labels, last scrape time, scrape duration, and any errors.

---

### Tool 14: `get_targets_metadata`
**Get metadata about metrics from specific scrape targets.**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `match_target` | string | No | Target label matcher |
| `metric` | string | No | Filter by metric name |
| `limit` | string | No | Max metadata entries |
| `prometheus_url` | string | No | Override URL |
| `org_id` | string | No | Organization ID |

**Examples:**

```json
// Get all metadata from the node exporter target
{ "name": "get_targets_metadata", "arguments": { "match_target": "{job=\"node\"}", "limit": "10" } }

// Get metadata for a specific metric across all targets
{ "name": "get_targets_metadata", "arguments": { "metric": "process_cpu_seconds_total" } }

// Get metadata from prometheus target, limited to 5
{ "name": "get_targets_metadata", "arguments": { "match_target": "{job=\"prometheus\"}", "limit": "5" } }
```

---

### Tool 15: `get_tsdb_stats`
**Get TSDB cardinality statistics (series count, label cardinality, memory usage).**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `limit` | string | No | Max stats entries |
| `prometheus_url` | string | No | Override URL |
| `org_id` | string | No | Organization ID |

```json
{ "name": "get_tsdb_stats", "arguments": {} }

// With limit
{ "name": "get_tsdb_stats", "arguments": { "limit": "5" } }
```
**Sample Output:** Head stats (NumSeries: 1420), top metrics by series count, top labels by value count, memory usage by label name.

---

### Tool 16: `list_label_names`
**Get all available label names.**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `matches` | array | No | Label matchers to filter |
| `start_time` | string | No | Start time (RFC3339) |
| `end_time` | string | No | End time (RFC3339) |
| `limit` | string | No | Max label names |
| `prometheus_url` | string | No | Override URL |
| `org_id` | string | No | Organization ID |

**Examples:**

```json
// Get all label names
{ "name": "list_label_names", "arguments": {} }

// Get label names only for prometheus job metrics
{ "name": "list_label_names", "arguments": { "matches": ["{job=\"prometheus\"}"] } }

// Get label names for node exporter metrics
{ "name": "list_label_names", "arguments": { "matches": ["{job=\"node\"}"] } }

// Get label names within a time window
{
  "name": "list_label_names",
  "arguments": {
    "start_time": "2026-03-26T22:00:00Z",
    "end_time": "2026-03-26T23:00:00Z"
  }
}
```

---

### Tool 17: `list_label_values`
**Get values for a specific label.**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `label` | string | **Yes** | Label name to get values for |
| `matches` | array | No | Label matchers to filter |
| `start_time` | string | No | Start time (RFC3339) |
| `end_time` | string | No | End time (RFC3339) |
| `limit` | string | No | Max values |
| `prometheus_url` | string | No | Override URL |
| `org_id` | string | No | Organization ID |

**Examples:**

```json
// List all job names
{ "name": "list_label_values", "arguments": { "label": "job" } }
// Output: node, prometheus

// List all instances
{ "name": "list_label_values", "arguments": { "label": "instance" } }
// Output: localhost:9090, localhost:9100

// List all metric names (first 20)
{ "name": "list_label_values", "arguments": { "label": "__name__", "limit": "20" } }

// List all HTTP handlers (filtered to prometheus job)
{ "name": "list_label_values", "arguments": { "label": "handler", "matches": ["{job=\"prometheus\"}"] } }

// List CPU modes from node exporter
{ "name": "list_label_values", "arguments": { "label": "mode", "matches": ["{__name__=\"node_cpu_seconds_total\"}"] } }

// List filesystem types
{ "name": "list_label_values", "arguments": { "label": "fstype", "matches": ["{job=\"node\"}"] } }

// List all HTTP status codes
{ "name": "list_label_values", "arguments": { "label": "code", "matches": ["{job=\"prometheus\"}"] } }
```

---

### Tool 18: `query_exemplars`
**Query exemplars for distributed tracing correlation.**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `query` | string | **Yes** | PromQL query to find exemplars for |
| `start` | string | **Yes** | Start time (RFC3339 or Unix) |
| `end` | string | **Yes** | End time (RFC3339 or Unix) |
| `prometheus_url` | string | No | Override URL |
| `org_id` | string | No | Organization ID |

**Examples:**

```json
// Query exemplars for HTTP requests
{
  "name": "query_exemplars",
  "arguments": {
    "query": "prometheus_http_requests_total",
    "start": "2026-03-26T22:00:00Z",
    "end": "2026-03-26T23:00:00Z"
  }
}

// Query exemplars for request duration histogram
{
  "name": "query_exemplars",
  "arguments": {
    "query": "prometheus_http_request_duration_seconds_bucket",
    "start": "2026-03-26T22:00:00Z",
    "end": "2026-03-26T23:00:00Z"
  }
}
```

> **Note:** Exemplars require your Prometheus to have exemplar storage enabled and instrumented services sending exemplars (typically via OpenTelemetry).

---

## Query Examples by Category

### Health & Status Checks

| Query | Tool | Description |
|-------|------|-------------|
| `check_ready` | check_ready | Is Prometheus ready? |
| `up` | execute_query | Which targets are up? |
| `absent(my_metric)` | execute_query | Is a metric missing? |
| `get_targets` | get_targets | Scrape target health |
| `get_build_info` | get_build_info | Prometheus version |

### CPU Monitoring

| Query | Tool | Description |
|-------|------|-------------|
| `rate(process_cpu_seconds_total[5m])` | execute_query | Process CPU usage rate |
| `100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)` | execute_query | Node CPU usage % |
| `rate(process_cpu_seconds_total[5m])` over 1h | execute_range_query | CPU trend |

### Memory Monitoring

| Query | Tool | Description |
|-------|------|-------------|
| `process_resident_memory_bytes / 1024 / 1024` | execute_query | Memory in MB |
| `process_resident_memory_bytes > 1000000` | execute_query | Processes over 1MB |
| Memory trend over 1h | execute_range_query | Memory usage trend |

### Disk Monitoring

| Query | Tool | Description |
|-------|------|-------------|
| `node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"} * 100` | execute_query | Disk space % |
| `node_filesystem_size_bytes` | execute_query | Total disk size |

### HTTP/API Monitoring

| Query | Tool | Description |
|-------|------|-------------|
| `rate(prometheus_http_requests_total[5m])` | execute_query | Request rate |
| `sum by (job) (rate(prometheus_http_requests_total[5m]))` | execute_query | Rate by job |
| `topk(5, prometheus_http_requests_total)` | execute_query | Top endpoints |
| `histogram_quantile(0.99, rate(prometheus_http_request_duration_seconds_bucket[5m]))` | execute_query | P99 latency |
| `sum(rate(prometheus_http_requests_total{code=~"5.."}[5m]))` | execute_query | Error rate |

### Discovery & Exploration

| Tool | Description |
|------|-------------|
| `list_label_names` | What labels exist? |
| `list_label_values(label="job")` | What jobs are being scraped? |
| `list_label_values(label="__name__")` | What metrics exist? |
| `find_series(matches=["{job=\"node\"}"])` | What series exist for node exporter? |
| `get_metric_metadata(metric="...")` | What does this metric mean? |
| `get_targets_metadata` | What metrics does each target expose? |

### Operational

| Tool | Description |
|------|-------------|
| `get_config` | Current Prometheus config |
| `get_flags` | Runtime flags |
| `get_runtime_info` | Goroutines, GOGC, retention |
| `get_tsdb_stats` | Series count, cardinality |
| `get_rules` | Recording & alerting rules |
| `get_alerts` | Currently firing alerts |
| `get_alertmanagers` | Configured AlertManagers |

---

## Multi-Tenancy & Org Support

For Mimir, Cortex, or Thanos multi-tenant setups, every tool accepts an `org_id` parameter.

### Option A: Global Org ID (Environment Variable)

Set `PROMETHEUS_ORGID` when starting the container. This applies to ALL requests:

```bash
docker run -d --name mcp-prometheus \
  -p 8080:8080 -p 9091:9091 \
  -e PROMETHEUS_URL=http://host.docker.internal:9090 \
  -e PROMETHEUS_ORGID=my-org-id \
  --add-host=host.docker.internal:host-gateway \
  mcp-prometheus:latest
```

Or in `docker-compose.yml`:

```yaml
environment:
  - PROMETHEUS_URL=http://host.docker.internal:9090
  - PROMETHEUS_ORGID=my-org-id
```

### Option B: Per-Request Org ID

Pass `org_id` in each tool call to query different tenants:

```json
{ "name": "execute_query", "arguments": { "query": "up", "org_id": "tenant-a" } }
{ "name": "execute_query", "arguments": { "query": "up", "org_id": "tenant-b" } }
```

### Option C: Static Tenant Mapping (With OAuth)

For group-based tenant mapping (requires `--enable-oauth`):

```bash
-e TENANCY_STATIC_GROUP_MAP='{"team-ops":["prod-eu","prod-us"],"team-dev":["staging"]}'
```

Or use `--static-tenants` for a flat list:

```bash
--static-tenants=tenant-a,tenant-b,tenant-c
```

### Pointing to a Different Prometheus/Mimir Instance

Every tool also accepts `prometheus_url` to override the server per-call:

```json
{
  "name": "execute_query",
  "arguments": {
    "query": "up",
    "prometheus_url": "http://mimir.internal:8080/prometheus",
    "org_id": "my-tenant"
  }
}
```

---

## Troubleshooting

### Container keeps restarting
Check logs:
```bash
docker logs mcp-prometheus
```
Common causes:
- Missing `serve` subcommand (should be in ENTRYPOINT)
- Missing `--transport sse` flag (defaults to stdio which exits immediately)

### Cannot connect to Prometheus
- Ensure Prometheus is running: `curl http://localhost:9090/-/ready`
- In Docker, use `host.docker.internal` (not `localhost`) to reach host services
- Ensure `--add-host=host.docker.internal:host-gateway` is set

### SSE endpoint returns nothing
- Check the container is running: `docker ps`
- Test health: `curl http://localhost:9091/healthz`
- Test SSE: `curl -s --max-time 3 http://localhost:8080/sse`

### MCP server not showing in VS Code
- Ensure `.vscode/mcp.json` is in your workspace root
- Reload VS Code window (`Cmd+Shift+P` > "Reload Window")
- Check the MCP panel for connection errors

### "Invalid session ID" errors
SSE sessions expire. This is normal for curl testing. VS Code MCP clients handle session management automatically.

### Port conflicts
```bash
# Check what's using ports 8080 or 9091
lsof -i :8080
lsof -i :9091
```

### Authentication
For Prometheus instances requiring auth:
```bash
-e PROMETHEUS_USERNAME=myuser
-e PROMETHEUS_PASSWORD=mypassword
# or
-e PROMETHEUS_TOKEN=my-bearer-token
```

---

## Advanced Examples

### 1. SRE Golden Signals

The four golden signals (latency, traffic, errors, saturation) are the foundation of SRE monitoring. Here's how to query each one.

#### Latency

```json
// P50 / P90 / P99 request latency
{ "name": "execute_query", "arguments": {
    "query": "histogram_quantile(0.50, rate(prometheus_http_request_duration_seconds_bucket[5m]))"
} }
{ "name": "execute_query", "arguments": {
    "query": "histogram_quantile(0.90, rate(prometheus_http_request_duration_seconds_bucket[5m]))"
} }
{ "name": "execute_query", "arguments": {
    "query": "histogram_quantile(0.99, rate(prometheus_http_request_duration_seconds_bucket[5m]))"
} }

// Average latency by handler
{ "name": "execute_query", "arguments": {
    "query": "rate(prometheus_http_request_duration_seconds_sum[5m]) / rate(prometheus_http_request_duration_seconds_count[5m])"
} }

// Apdex score (satisfied < 0.1s, tolerating < 0.5s)
{ "name": "execute_query", "arguments": {
    "query": "(sum(rate(prometheus_http_request_duration_seconds_bucket{le=\"0.1\"}[5m])) + sum(rate(prometheus_http_request_duration_seconds_bucket{le=\"0.5\"}[5m]))) / 2 / sum(rate(prometheus_http_request_duration_seconds_count[5m]))"
} }
```

#### Traffic

```json
// Total request rate across all handlers
{ "name": "execute_query", "arguments": {
    "query": "sum(rate(prometheus_http_requests_total[5m]))"
} }

// Request rate by handler (top 10 busiest endpoints)
{ "name": "execute_query", "arguments": {
    "query": "topk(10, sum by (handler) (rate(prometheus_http_requests_total[5m])))"
} }

// Request rate trend over 24 hours
{
  "name": "execute_range_query",
  "arguments": {
    "query": "sum(rate(prometheus_http_requests_total[5m]))",
    "start": "2026-03-25T23:00:00Z",
    "end": "2026-03-26T23:00:00Z",
    "step": "15m"
  }
}
```

#### Errors

```json
// Error rate (5xx responses)
{ "name": "execute_query", "arguments": {
    "query": "sum(rate(prometheus_http_requests_total{code=~\"5..\"}[5m])) / sum(rate(prometheus_http_requests_total[5m])) * 100"
} }

// Error rate by handler
{ "name": "execute_query", "arguments": {
    "query": "sum by (handler) (rate(prometheus_http_requests_total{code=~\"5..\"}[5m])) / sum by (handler) (rate(prometheus_http_requests_total[5m])) * 100"
} }

// Non-200 response breakdown by status code
{ "name": "execute_query", "arguments": {
    "query": "sum by (code) (rate(prometheus_http_requests_total{code!=\"200\"}[5m]))"
} }
```

#### Saturation

```json
// CPU saturation — usage percentage
{ "name": "execute_query", "arguments": {
    "query": "100 - (avg by (instance) (rate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100)"
} }
// Sample output: {instance="localhost:9100"} => 19.81%

// Memory saturation — heap in use vs total
{ "name": "execute_query", "arguments": {
    "query": "go_memstats_heap_inuse_bytes / 1024 / 1024"
} }
// Sample output: node=3.1MB, prometheus=33.2MB

// File descriptor saturation — used vs limit (%)
{ "name": "execute_query", "arguments": {
    "query": "process_open_fds / process_max_fds * 100"
} }
// Sample output: node=0.07%, prometheus=0.6%

// Goroutine count (Go service saturation)
{ "name": "execute_query", "arguments": {
    "query": "go_goroutines"
} }
// Sample output: node=7, prometheus=38
```

---

### 2. SLO & Error Budget Queries

```json
// Availability SLI — percentage of non-error requests
{ "name": "execute_query", "arguments": {
    "query": "sum(rate(prometheus_http_requests_total{code!~\"5..\"}[1h])) / sum(rate(prometheus_http_requests_total[1h])) * 100"
} }
// Sample output: 100% (no 5xx errors)

// Error budget remaining (99.9% SLO over 30 days)
// If error_rate < 0.1%, budget is positive
{ "name": "execute_query", "arguments": {
    "query": "1 - (sum(rate(prometheus_http_requests_total{code=~\"5..\"}[24h])) / sum(rate(prometheus_http_requests_total[24h])))"
} }

// Burn rate: how fast you're consuming error budget
// burn_rate > 1 means you'll exhaust budget before the window ends
{ "name": "execute_query", "arguments": {
    "query": "(sum(rate(prometheus_http_requests_total{code=~\"5..\"}[1h])) / sum(rate(prometheus_http_requests_total[1h]))) / (1 - 0.999)"
} }

// Availability trend over 7 days (range query)
{
  "name": "execute_range_query",
  "arguments": {
    "query": "sum(rate(prometheus_http_requests_total{code!~\"5..\"}[1h])) / sum(rate(prometheus_http_requests_total[1h])) * 100",
    "start": "2026-03-19T00:00:00Z",
    "end": "2026-03-26T00:00:00Z",
    "step": "1h"
  }
}
```

---

### 3. Capacity Planning & Prediction

```json
// Predict disk free space in 24 hours (linear extrapolation)
{ "name": "execute_query", "arguments": {
    "query": "predict_linear(node_filesystem_avail_bytes{mountpoint=\"/\"}[1h], 24*3600) / 1024 / 1024 / 1024"
} }
// Sample output: -30.26 GB (disk will be full within 24h!)

// Predict disk free in 7 days
{ "name": "execute_query", "arguments": {
    "query": "predict_linear(node_filesystem_avail_bytes{mountpoint=\"/\"}[6h], 7*24*3600) / 1024 / 1024 / 1024"
} }

// Days until disk full (hours_remaining / 24)
{ "name": "execute_query", "arguments": {
    "query": "node_filesystem_avail_bytes{mountpoint=\"/\"} / (deriv(node_filesystem_avail_bytes{mountpoint=\"/\"}[1h]) * -1) / 3600 / 24"
} }

// Memory growth rate (bytes per second)
{ "name": "execute_query", "arguments": {
    "query": "deriv(process_resident_memory_bytes[1h])"
} }

// Series count growth rate (cardinality trend)
{
  "name": "execute_range_query",
  "arguments": {
    "query": "prometheus_tsdb_head_series",
    "start": "2026-03-25T00:00:00Z",
    "end": "2026-03-26T00:00:00Z",
    "step": "1h"
  }
}
```

---

### 4. System Resource Deep Dive

#### CPU

```json
// CPU mode breakdown — percentage per mode (idle, user, system, iowait)
{ "name": "execute_query", "arguments": {
    "query": "sum by (mode) (rate(node_cpu_seconds_total[5m])) / ignoring(mode) group_left sum(rate(node_cpu_seconds_total[5m])) * 100"
} }
// Sample output: idle=83%, system=7.7%, user=9.3%, nice=0%

// Per-core CPU usage
{ "name": "execute_query", "arguments": {
    "query": "1 - rate(node_cpu_seconds_total{mode=\"idle\"}[5m])"
} }

// System load average (1m, 5m, 15m)
{ "name": "execute_query", "arguments": { "query": "node_load1" } }
{ "name": "execute_query", "arguments": { "query": "node_load5" } }
{ "name": "execute_query", "arguments": { "query": "node_load15" } }
// Sample output: node_load1 = 2.73

// CPU trend over 6 hours
{
  "name": "execute_range_query",
  "arguments": {
    "query": "100 - (avg by (instance) (rate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100)",
    "start": "2026-03-26T17:00:00Z",
    "end": "2026-03-26T23:00:00Z",
    "step": "10m"
  }
}
```

#### Memory

```json
// Process memory in MB (all processes)
{ "name": "execute_query", "arguments": {
    "query": "process_resident_memory_bytes / 1024 / 1024"
} }

// Go heap breakdown: in-use, allocated, system
{ "name": "execute_query", "arguments": {
    "query": "go_memstats_heap_inuse_bytes / 1024 / 1024"
} }
{ "name": "execute_query", "arguments": {
    "query": "go_memstats_heap_alloc_bytes / 1024 / 1024"
} }
{ "name": "execute_query", "arguments": {
    "query": "go_memstats_sys_bytes / 1024 / 1024"
} }

// P95 memory usage over the last hour (subquery)
{ "name": "execute_query", "arguments": {
    "query": "quantile_over_time(0.95, process_resident_memory_bytes[1h:]) / 1024 / 1024"
} }
// Sample output: node=9.99MB

// Memory trend over 6 hours
{
  "name": "execute_range_query",
  "arguments": {
    "query": "process_resident_memory_bytes / 1024 / 1024",
    "start": "2026-03-26T17:00:00Z",
    "end": "2026-03-26T23:00:00Z",
    "step": "10m"
  }
}
```

#### Disk

```json
// Disk space: used, available, total per mountpoint
{ "name": "execute_query", "arguments": {
    "query": "(node_filesystem_size_bytes - node_filesystem_avail_bytes) / 1024 / 1024 / 1024"
} }

// Disk usage percentage per mountpoint
{ "name": "execute_query", "arguments": {
    "query": "(1 - node_filesystem_avail_bytes / node_filesystem_size_bytes) * 100"
} }

// Disk I/O: read and write throughput MB/s
{ "name": "execute_query", "arguments": {
    "query": "rate(node_disk_read_bytes_total[5m]) / 1024 / 1024"
} }
// Sample output: disk0 = 15.96 MB/s
{ "name": "execute_query", "arguments": {
    "query": "rate(node_disk_written_bytes_total[5m]) / 1024 / 1024"
} }

// Inode usage percentage
{ "name": "execute_query", "arguments": {
    "query": "(1 - node_filesystem_files_free / node_filesystem_files) * 100"
} }
```

#### Network

```json
// Network receive/transmit MB/s per interface (excluding loopback)
{ "name": "execute_query", "arguments": {
    "query": "rate(node_network_receive_bytes_total{device!=\"lo\"}[5m]) / 1024 / 1024"
} }
// Sample output: en0 = 0.011 MB/s
{ "name": "execute_query", "arguments": {
    "query": "rate(node_network_transmit_bytes_total{device!=\"lo\"}[5m]) / 1024 / 1024"
} }
// Sample output: en0 = 0.014 MB/s

// Total network throughput trend over 1 hour
{
  "name": "execute_range_query",
  "arguments": {
    "query": "sum(rate(node_network_receive_bytes_total{device!=\"lo\"}[5m])) / 1024 / 1024",
    "start": "2026-03-26T22:00:00Z",
    "end": "2026-03-26T23:00:00Z",
    "step": "5m"
  }
}

// Network errors per interface
{ "name": "execute_query", "arguments": {
    "query": "rate(node_network_receive_errs_total[5m]) + rate(node_network_transmit_errs_total[5m])"
} }

// Packets per second
{ "name": "execute_query", "arguments": {
    "query": "sum by (device) (rate(node_network_receive_packets_total{device!=\"lo\"}[5m]))"
} }
```

---

### 5. Garbage Collection & Go Runtime

```json
// GC average pause duration
{ "name": "execute_query", "arguments": {
    "query": "rate(go_gc_duration_seconds_sum[5m]) / rate(go_gc_duration_seconds_count[5m])"
} }
// Sample output: node=0.52ms, prometheus=2.39ms

// GC pause rate (how often GC runs)
{ "name": "execute_query", "arguments": {
    "query": "rate(go_gc_duration_seconds_count[5m])"
} }

// GC total cycles
{ "name": "execute_query", "arguments": {
    "query": "go_gc_cycles_total_gc_cycles_total"
} }

// Go memory allocation rate
{ "name": "execute_query", "arguments": {
    "query": "rate(go_gc_heap_allocs_bytes_total[5m]) / 1024 / 1024"
} }

// GC pause trend over 6 hours
{
  "name": "execute_range_query",
  "arguments": {
    "query": "rate(go_gc_duration_seconds_sum[5m])",
    "start": "2026-03-26T17:00:00Z",
    "end": "2026-03-26T23:00:00Z",
    "step": "30m"
  }
}

// GOGC and GOMEMLIMIT settings
{ "name": "execute_query", "arguments": { "query": "go_gc_gogc_percent" } }
{ "name": "execute_query", "arguments": { "query": "go_gc_gomemlimit_bytes / 1024 / 1024 / 1024" } }
```

---

### 6. Prometheus Self-Monitoring

```json
// Process uptime (seconds since start)
{ "name": "execute_query", "arguments": {
    "query": "time() - process_start_time_seconds"
} }
// Sample output: node=241407s (~2.8 days), prometheus=241407s

// Scrape duration — which targets are slowest?
{ "name": "execute_query", "arguments": {
    "query": "topk(5, scrape_duration_seconds)"
} }
// Sample output: node=0.046s, prometheus=0.030s

// Samples scraped per target
{ "name": "execute_query", "arguments": {
    "query": "scrape_samples_scraped"
} }
// Sample output: node=452, prometheus=1096

// Scrape success vs failure
{ "name": "execute_query", "arguments": {
    "query": "up == 0"
} }

// TSDB head series count over time
{
  "name": "execute_range_query",
  "arguments": {
    "query": "prometheus_tsdb_head_series",
    "start": "2026-03-26T00:00:00Z",
    "end": "2026-03-26T23:00:00Z",
    "step": "1h"
  }
}

// Ingestion rate (samples per second)
{ "name": "execute_query", "arguments": {
    "query": "rate(prometheus_tsdb_head_samples_appended_total[5m])"
} }

// Query engine latency
{ "name": "execute_query", "arguments": {
    "query": "rate(prometheus_engine_query_duration_seconds_sum[5m]) / rate(prometheus_engine_query_duration_seconds_count[5m])"
} }

// WAL corruption count
{ "name": "execute_query", "arguments": {
    "query": "prometheus_tsdb_wal_corruptions_total"
} }
```

---

### 7. Cardinality & TSDB Management

```json
// Total active series
{ "name": "get_tsdb_stats", "arguments": { "limit": "10" } }
// Sample output: NumSeries: 1558, top metric: prometheus_http_request_duration_seconds_bucket (240 series)

// Top 10 metrics by series count (using TSDB stats)
{ "name": "get_tsdb_stats", "arguments": { "limit": "10" } }

// Find all series for a high-cardinality metric
{ "name": "find_series", "arguments": {
    "matches": ["{__name__=\"prometheus_http_request_duration_seconds_bucket\"}"],
    "limit": "20"
} }

// Count series per job
{ "name": "execute_query", "arguments": {
    "query": "count by (job) ({__name__!=\"\"})"
} }

// Count distinct label values for a label
{ "name": "execute_query", "arguments": {
    "query": "count(count by (handler) (prometheus_http_requests_total))"
} }

// Which labels are highest cardinality? Use TSDB stats:
// LabelValueCountByLabelName shows: __name__=350, le=79, handler=58, device=30

// Find metrics matching a pattern (regex)
{ "name": "find_series", "arguments": {
    "matches": ["{__name__=~\"prometheus_http.*\"}"],
    "limit": "10"
} }

// What metric types are being scraped?
{ "name": "get_targets_metadata", "arguments": {
    "match_target": "{job=\"node\"}",
    "limit": "20"
} }
```

---

### 8. Advanced PromQL Techniques

#### Subqueries

```json
// P95 memory usage over the last hour, sampled every 5 minutes
{ "name": "execute_query", "arguments": {
    "query": "quantile_over_time(0.95, process_resident_memory_bytes[1h:])"
} }
// Sample output: 10472652 bytes (~10MB)

// Max CPU over the last hour
{ "name": "execute_query", "arguments": {
    "query": "max_over_time((100 - avg by (instance) (rate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100)[1h:])"
} }

// Min memory in last 6 hours
{ "name": "execute_query", "arguments": {
    "query": "min_over_time(process_resident_memory_bytes[6h:]) / 1024 / 1024"
} }

// Standard deviation of request rate (detect anomalies)
{ "name": "execute_query", "arguments": {
    "query": "stddev_over_time(rate(prometheus_http_requests_total[5m])[1h:])"
} }
```

#### irate vs rate

```json
// rate: average rate over the entire window (smoother)
{ "name": "execute_query", "arguments": {
    "query": "rate(prometheus_http_requests_total[5m])"
} }

// irate: instant rate between the last two samples (spikier, more responsive)
{ "name": "execute_query", "arguments": {
    "query": "irate(prometheus_http_requests_total[5m])"
} }
// Use irate for dashboards (catches spikes), rate for alerting (avoids false positives)
```

#### Label Manipulation

```json
// Extract hostname from instance label
{ "name": "execute_query", "arguments": {
    "query": "label_replace(up, \"host\", \"$1\", \"instance\", \"(.*):(.*)\") "
} }
// Sample output: up{host="localhost", instance="localhost:9090"} => 1

// Join/combine metrics from different sources
{ "name": "execute_query", "arguments": {
    "query": "process_resident_memory_bytes * on(instance, job) group_left up"
} }
```

#### Absent & Staleness Detection

```json
// Check if a critical metric is missing
{ "name": "execute_query", "arguments": {
    "query": "absent(up{job=\"critical-service\"})"
} }
// Returns 1 if metric doesn't exist (alert on this!)

// absent_over_time: was a metric missing during a window?
{ "name": "execute_query", "arguments": {
    "query": "absent_over_time(up{job=\"prometheus\"}[1h])"
} }

// Count how many targets are down
{ "name": "execute_query", "arguments": {
    "query": "count(up == 0)"
} }
```

#### Boolean & Conditional Queries

```json
// Show only targets using more than 10MB memory
{ "name": "execute_query", "arguments": {
    "query": "process_resident_memory_bytes > 10 * 1024 * 1024"
} }

// Binary: is CPU above 80%?
{ "name": "execute_query", "arguments": {
    "query": "(100 - avg by (instance) (rate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100) > 80"
} }

// Clamp values (floor/ceiling)
{ "name": "execute_query", "arguments": {
    "query": "clamp_min(clamp_max(node_load1, 10), 0)"
} }
```

---

### 9. Multi-Tenant / Multi-Org Workflows

```json
// Query a specific tenant
{ "name": "execute_query", "arguments": {
    "query": "up",
    "org_id": "team-platform"
} }

// Compare targets across two tenants (run separately)
{ "name": "execute_query", "arguments": { "query": "count(up)", "org_id": "prod-eu" } }
{ "name": "execute_query", "arguments": { "query": "count(up)", "org_id": "prod-us" } }

// Check readiness per tenant
{ "name": "check_ready", "arguments": { "org_id": "staging" } }

// List metrics for a specific tenant
{ "name": "list_label_values", "arguments": {
    "label": "__name__",
    "limit": "20",
    "org_id": "team-platform"
} }

// Compare cardinality per tenant
{ "name": "get_tsdb_stats", "arguments": { "org_id": "prod-eu" } }
{ "name": "get_tsdb_stats", "arguments": { "org_id": "prod-us" } }

// Query a different Prometheus/Mimir instance entirely
{ "name": "execute_query", "arguments": {
    "query": "up",
    "prometheus_url": "http://mimir-prod.internal:8080/prometheus",
    "org_id": "prod-tenant"
} }
```

---

### 10. Incident Response Playbook Queries

Use these as a step-by-step investigation when something goes wrong.

#### Step 1: Is everything up?

```json
{ "name": "check_ready", "arguments": {} }
{ "name": "execute_query", "arguments": { "query": "up" } }
{ "name": "get_alerts", "arguments": {} }
```

#### Step 2: What's the resource situation?

```json
// CPU, memory, disk, FDs — all at once
{ "name": "execute_query", "arguments": {
    "query": "100 - (avg by (instance) (rate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100)"
} }
{ "name": "execute_query", "arguments": {
    "query": "process_resident_memory_bytes / 1024 / 1024"
} }
{ "name": "execute_query", "arguments": {
    "query": "(1 - node_filesystem_avail_bytes{mountpoint=\"/\"} / node_filesystem_size_bytes{mountpoint=\"/\"}) * 100"
} }
{ "name": "execute_query", "arguments": {
    "query": "process_open_fds / process_max_fds * 100"
} }
```

#### Step 3: When did it start?

```json
// Look at the last 6 hours for CPU and error rate changes
{
  "name": "execute_range_query",
  "arguments": {
    "query": "100 - (avg by (instance) (rate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100)",
    "start": "2026-03-26T17:00:00Z",
    "end": "2026-03-26T23:00:00Z",
    "step": "5m"
  }
}
{
  "name": "execute_range_query",
  "arguments": {
    "query": "sum(rate(prometheus_http_requests_total{code=~\"5..\"}[5m]))",
    "start": "2026-03-26T17:00:00Z",
    "end": "2026-03-26T23:00:00Z",
    "step": "5m"
  }
}
```

#### Step 4: Check the configuration

```json
{ "name": "get_config", "arguments": {} }
{ "name": "get_flags", "arguments": {} }
{ "name": "get_runtime_info", "arguments": {} }
```

#### Step 5: What changed?

```json
// Config reload — did it succeed?
{ "name": "get_runtime_info", "arguments": {} }
// Check: ReloadConfigSuccess=true/false, LastConfigTime

// Were any targets added or removed?
{ "name": "get_targets", "arguments": {} }

// Any new rules?
{ "name": "get_rules", "arguments": {} }
```

---

### 11. Combined Multi-Tool Workflows

These examples show how to chain multiple tools together for end-to-end analysis.

#### "Discover → Understand → Query" Workflow

```json
// 1. What jobs exist?
{ "name": "list_label_values", "arguments": { "label": "job" } }

// 2. What metrics does that job expose?
{ "name": "list_label_values", "arguments": {
    "label": "__name__",
    "matches": ["{job=\"node\"}"],
    "limit": "30"
} }

// 3. What does a specific metric mean?
{ "name": "get_metric_metadata", "arguments": { "metric": "node_cpu_seconds_total" } }

// 4. What labels does it have?
{ "name": "list_label_names", "arguments": {
    "matches": ["{__name__=\"node_cpu_seconds_total\"}"]
} }

// 5. What values exist for a key label?
{ "name": "list_label_values", "arguments": {
    "label": "mode",
    "matches": ["{__name__=\"node_cpu_seconds_total\"}"]
} }

// 6. Now query it with full understanding
{ "name": "execute_query", "arguments": {
    "query": "sum by (mode) (rate(node_cpu_seconds_total[5m])) / ignoring(mode) group_left sum(rate(node_cpu_seconds_total[5m])) * 100"
} }
```

#### "Health Check → Diagnose → Predict" Workflow

```json
// 1. Overall health
{ "name": "check_ready", "arguments": {} }
{ "name": "execute_query", "arguments": { "query": "up" } }

// 2. Scrape health
{ "name": "get_targets", "arguments": {} }
{ "name": "execute_query", "arguments": { "query": "scrape_duration_seconds" } }

// 3. Current resource usage
{ "name": "execute_query", "arguments": {
    "query": "process_resident_memory_bytes / 1024 / 1024"
} }

// 4. Memory trend (is it growing?)
{
  "name": "execute_range_query",
  "arguments": {
    "query": "process_resident_memory_bytes / 1024 / 1024",
    "start": "2026-03-26T17:00:00Z",
    "end": "2026-03-26T23:00:00Z",
    "step": "15m"
  }
}

// 5. Predict — when will disk run out?
{ "name": "execute_query", "arguments": {
    "query": "predict_linear(node_filesystem_avail_bytes{mountpoint=\"/\"}[6h], 7*24*3600) / 1024 / 1024 / 1024"
} }

// 6. Cardinality — is series count growing?
{ "name": "get_tsdb_stats", "arguments": { "limit": "5" } }
```

---

### 12. Asking AI Natural Language Questions

When using the MCP server with an AI assistant in VS Code, you can ask questions in plain English. The AI will select the right tools and queries automatically.

**Example prompts you can ask the AI:**

- "Are all my targets healthy?"
- "What's the CPU usage on my node exporter?"
- "Show me the memory trend for the last 6 hours"
- "Which endpoint has the highest latency?"
- "How much disk space is left and when will it run out?"
- "What metrics does the node exporter expose?"
- "Compare the error rate between the last hour and the hour before"
- "Is my Prometheus config correct? Show me the scrape configs"
- "What are the top 5 highest-cardinality metrics?"
- "Run a P99 latency check across all handlers"
- "Check if any alerts are firing"
- "Query the staging tenant for its target count"
- "How many goroutines is Prometheus running?"
- "Show me the GC pause duration trend"
- "What happened to CPU usage around 3pm today?"

The AI will translate these into the appropriate tool calls, interpret the results, and explain the findings in context.

---

## Quick Reference Card

```
HEALTH:     check_ready, get_targets, get_alerts
QUERY:      execute_query, execute_range_query
DISCOVER:   find_series, list_label_names, list_label_values
METADATA:   get_metric_metadata, get_targets_metadata
CONFIG:     get_config, get_flags, get_runtime_info, get_build_info
RULES:      get_rules, get_alerts, get_alertmanagers
STORAGE:    get_tsdb_stats
TRACING:    query_exemplars
```

Every tool accepts optional `prometheus_url` and `org_id` for multi-tenant use.
