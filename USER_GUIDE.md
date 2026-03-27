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
