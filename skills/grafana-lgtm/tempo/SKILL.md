---
name: tempo
license: Apache-2.0
description: >
  Grafana Tempo distributed tracing backend. Covers TraceQL query language (span selectors,
  attribute scopes, pipeline operators, structural operators, metrics functions), trace ingestion
  via OTLP/Jaeger/Zipkin, Tempo architecture (distributor/ingester/compactor/querier/metrics-generator),
  full configuration reference with YAML, metrics-from-traces (span metrics, service graphs,
  TraceQL metrics), deployment modes (monolithic/microservices/Helm/Kubernetes), multi-tenancy,
  performance tuning, caching, and HTTP API. Use when working with distributed traces, writing
  TraceQL queries, deploying Tempo, configuring trace pipelines, or setting up Grafana-Tempo
  integrations (traces-to-logs, traces-to-metrics, traces-to-profiles).
---

# Grafana Tempo - Distributed Tracing Backend

Grafana Tempo is an open-source, high-scale distributed tracing backend. It is:
- **Cost-efficient**: only requires object storage (S3, GCS, Azure) to operate
- **Deeply integrated**: with Grafana, Mimir, Prometheus, Loki, and Pyroscope
- **Protocol-agnostic**: accepts OTLP, Jaeger, Zipkin, OpenCensus, Kafka

## Quick Reference Links

- [TraceQL Language Reference](./references/traceql.md) - query syntax, operators, examples, metrics functions
- [Configuration Reference](./references/configuration.md) - all YAML config blocks with defaults
- [Architecture and Operations](./references/architecture-and-operations.md) - components, deployment, tuning
- [Metrics from Traces](./references/metrics-from-traces.md) - span metrics, service graphs, TraceQL metrics
- [API Reference](./references/api.md) - HTTP endpoints, ingestion, search, metrics queries

---

## What is Distributed Tracing?

A **trace** represents the lifecycle of a request as it passes through multiple services. It consists of:
- **Spans**: Individual units of work with start time, duration, attributes, and status
- **Trace ID**: Shared identifier across all spans in a request
- **Parent-child relationships**: Spans form a tree showing causality

Traces enable:
- Root cause analysis for service outages
- Understanding service dependencies
- Identifying latency bottlenecks
- Correlating events across microservices

---

## Architecture Overview

```
Applications
    |
    | (OTLP 4317/4318, Jaeger 14250/14268, Zipkin 9411)
    v
[Distributor]  ----  hashes traceID, routes to N ingesters
    |
    |---> [Ingester]  (WAL + Parquet block assembly, flush to object store)
    |
    |---> [Metrics Generator]  (optional: derives RED metrics -> Prometheus)
    
Query path:
Grafana  -->  [Query Frontend]  (shards queries)
                    |
              [Querier pool]
              /           \
    [Ingesters]     [Object Storage]
    (recent)        (historical blocks)
```

### Core Components

| Component | Role | Default Ports |
|-----------|------|---------------|
| Distributor | Receives spans, routes by traceID hash | 4317 (gRPC), 4318 (HTTP) |
| Ingester | Buffers in memory, flushes to storage | - |
| Query Frontend | Query orchestrator, shards across queriers | 3200 (HTTP) |
| Querier | Executes search jobs against storage | - |
| Compactor | Merges blocks, enforces retention | - |
| Metrics Generator | Derives RED metrics from spans | - |

---

## TraceQL - The Query Language

TraceQL queries filter traces by span properties. Structure: `{ filters } | pipeline`

### Attribute Scopes

```traceql
span.http.status_code        # span-level attribute
resource.service.name        # resource attribute (from SDK)
name                         # intrinsic: span operation name
status                       # intrinsic: ok | error | unset
duration                     # intrinsic: span duration
kind                         # intrinsic: server | client | producer | consumer | internal
traceDuration                # intrinsic: entire trace duration
rootServiceName              # intrinsic: service of the root span
rootName                     # intrinsic: operation name of the root span
```

### Operators

```
=   !=   >   <   >=   <=      # comparison
=~  !~                         # regex match (Go RE2)
&&  ||  !                      # logical
```

### Essential Examples

```traceql
# All errors
{ status = error }

# Slow requests from a service
{ resource.service.name = "frontend" && duration > 1s }

# HTTP 5xx errors
{ span.http.status_code >= 500 }

# Count errors per trace (more than 2)
{ status = error } | count() >= 2

# Group by service
{ status = error } | by(resource.service.name)

# P99 latency grouping
{ kind = server } | avg(duration) by(resource.service.name)

# Select specific fields
{ status = error } | select(span.http.url, duration, resource.service.name)

# Structural: server span with downstream error
{ kind = server } >> { status = error }

# Both conditions present (any relationship)
{ span.db.system = "redis" } && { span.db.system = "postgresql" }

# Find most recent (deterministic)
{ resource.service.name = "api" } with (most_recent=true)
```

### TraceQL Metrics

```traceql
# Error rate per service
{ status = error } | rate() by (resource.service.name)

# P99 latency
{ kind = server } | quantile_over_time(duration, .99) by (resource.service.name)

# With exemplars
{ kind = server } | quantile_over_time(duration, .99) by (resource.service.name) with (exemplars=true)
```

---

## Deployment

### Quick Start (Docker Compose)

```bash
git clone https://github.com/grafana/tempo.git
cd tempo/example/docker-compose/local
mkdir tempo-data
docker compose up -d
# Grafana at http://localhost:3000, Tempo API at http://localhost:3200
```

### Minimal Single-Node Config

```yaml
server:
  http_listen_port: 3200

distributor:
  receivers:
    otlp:
      protocols:
        grpc:
          endpoint: 0.0.0.0:4317
        http:
          endpoint: 0.0.0.0:4318

ingester:
  lifecycler:
    ring:
      replication_factor: 1

compactor:
  compaction:
    block_retention: 336h    # 14 days

storage:
  trace:
    backend: local
    local:
      path: /var/tempo/traces
    wal:
      path: /var/tempo/wal

memberlist:
  abort_if_cluster_join_fails: false
  join_members: []
```

### Production (S3 + Microservices)

```yaml
storage:
  trace:
    backend: s3
    s3:
      bucket: tempo-traces
      endpoint: s3.amazonaws.com
      region: us-east-1
      # Use IRSA/IAM roles (preferred over access keys)

compactor:
  compaction:
    block_retention: 336h    # Override per-tenant in overrides section

memberlist:
  join_members:
    - tempo-1:7946
    - tempo-2:7946
    - tempo-3:7946

ingester:
  lifecycler:
    ring:
      replication_factor: 3
```

### Kubernetes (Helm)

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm install tempo grafana/tempo-distributed \
  --set storage.trace.backend=s3 \
  --set storage.trace.s3.bucket=my-tempo-bucket \
  --set storage.trace.s3.region=us-east-1
```

---

## Sending Traces to Tempo

### Via Grafana Alloy (Recommended)

```alloy
// alloy.river
otelcol.receiver.otlp "default" {
  grpc { endpoint = "0.0.0.0:4317" }
  http { endpoint = "0.0.0.0:4318" }
  output {
    traces = [otelcol.exporter.otlp.tempo.input]
  }
}

otelcol.exporter.otlp "tempo" {
  client {
    endpoint = "tempo:4317"
    tls { insecure = true }
  }
}
```

### Via OpenTelemetry Collector

```yaml
exporters:
  otlp:
    endpoint: tempo:4317
    tls:
      insecure: true
    # For multi-tenancy:
    headers:
      x-scope-orgid: my-tenant

service:
  pipelines:
    traces:
      receivers: [otlp]
      exporters: [otlp]
```

### Direct HTTP (OTLP)

```bash
curl -X POST -H 'Content-Type: application/json' \
  http://localhost:4318/v1/traces \
  -d '{"resourceSpans": [{"resource": {"attributes": [{"key": "service.name", "value": {"stringValue": "my-service"}}]}, "scopeSpans": [{"spans": [{"traceId": "5B8EFFF798038103D269B633813FC700", "spanId": "EEE19B7EC3C1B100", "name": "my-op", "startTimeUnixNano": 1689969302000000000, "endTimeUnixNano": 1689969302500000000, "kind": 2}]}]}]}'
```

---

## Metrics from Traces

### Enable Metrics Generator

```yaml
metrics_generator:
  storage:
    path: /var/tempo/generator/wal
    remote_write:
      - url: http://prometheus:9090/api/v1/write
        send_exemplars: true

overrides:
  defaults:
    metrics_generator:
      processors: [service-graphs, span-metrics, local-blocks]
```

### Processor Types

**Service Graphs**: Visualizes service topology and latency
- Output: `traces_service_graph_request_total`, `traces_service_graph_request_failed_total`, duration histograms

**Span Metrics**: RED metrics per span
- Output: `traces_spanmetrics_calls_total`, `traces_spanmetrics_duration_seconds_*`
- Labels: service, span_name, span_kind, status_code + custom dimensions

**Local Blocks**: Enables TraceQL metrics queries on recent data

---

## Multi-Tenancy

```yaml
# Enable in Tempo config
multitenancy_enabled: true
```

All requests require `X-Scope-OrgID` header.

```yaml
# OpenTelemetry Collector
exporters:
  otlp:
    headers:
      x-scope-orgid: tenant-id

# Grafana datasource
jsonData:
  httpHeaderName1: "X-Scope-OrgID"
secureJsonData:
  httpHeaderValue1: "tenant-id"
```

---

## Grafana Integration

### Data Source Configuration

```yaml
datasources:
  - name: Tempo
    type: tempo
    url: http://tempo:3200
    jsonData:
      # Link traces to logs
      tracesToLogsV2:
        datasourceUid: loki-uid
        filterByTraceID: true
        tags: [{key: "service.name", value: "app"}]

      # Link traces to metrics
      tracesToMetrics:
        datasourceUid: prometheus-uid
        tags: [{key: "service.name", value: "service"}]
        queries:
          - name: Error Rate
            query: 'sum(rate(traces_spanmetrics_calls_total{$$__tags, status_code="STATUS_CODE_ERROR"}[5m]))'

      # Link traces to profiles (Pyroscope)
      tracesToProfiles:
        datasourceUid: pyroscope-uid
        tags: [{key: "service.name", value: "service_name"}]

      # Service map from span metrics
      serviceMap:
        datasourceUid: prometheus-uid
```

### Key Grafana Features

- **Explore > Tempo**: Search by TraceQL, trace ID, or tag filters
- **Service Graph tab**: Visual service topology with RED metrics
- **Traces Drilldown**: `/a/grafana-exploretraces-app` - no TraceQL required
- **Exemplars**: Click metric spike -> jump directly to responsible trace
- **Derived fields in Loki**: Click trace ID in log -> jump to trace in Tempo

---

## API Quick Reference

```bash
# Search traces
GET /api/search?q={status=error}&limit=20&start=<unix>&end=<unix>

# Get trace by ID
GET /api/traces/<traceID>
GET /api/v2/traces/<traceID>

# List all tag names
GET /api/search/tags

# Get values for a tag
GET /api/search/tag/service.name/values

# TraceQL metrics (time series)
GET /api/metrics/query_range?q={status=error}|rate()&start=...&end=...&step=60

# Health check
GET /ready
```

---

## Performance Tuning Summary

| Problem | Solution |
|---------|----------|
| Slow searches | Scale queriers horizontally; scale compactors to reduce block count |
| High memory on queriers | Reduce `max_concurrent_queries`; lower `target_bytes_per_job` |
| High memory on ingesters | Reduce `max_block_bytes`; lower per-tenant trace limits |
| Slow attribute queries | Add dedicated Parquet columns for frequent attributes |
| Cache miss rate high | Increase cache size; tune `cache_min_compaction_level` |
| Rate limited (429) | Raise `max_outstanding_per_tenant` or increase per-tenant ingestion limits |
| Memcached connection errors | Increase memcached connection limit (`-c 4096`) |

---

## Best Practices

### Instrumentation
- Follow **OpenTelemetry semantic conventions** for attribute names
- Use `span.` prefix for span attributes, `resource.` for process context
- Keep attributes meaningful - avoid metrics/logs as span attributes
- Limit attributes to max ~128 per span (OTel default)
- Use **span linking** for batch processing (instead of huge fan-out traces)
- Create spans for: external calls, significant loops, operations with variable latency
- Avoid creating spans for every function call

### Deployment
- Use **replication factor 3** for production HA
- **Object storage** required for distributed deployments (not local)
- Enable **dedicated attribute columns** for your most-queried attributes
- Set appropriate **block retention** per tenant via overrides
- Monitor `tempo_ingester_live_traces` to detect memory pressure early

### Querying
- Use **time bounds** (`start`/`end`) to limit search scope
- Use **structural operators** for root cause analysis patterns
- Prefer `attribute != nil` for existence checks
- Use `with (most_recent=true)` when you need deterministic recent results
- Scope tag discovery with a TraceQL query to reduce noise

---

## Ports Reference

| Port | Protocol | Purpose |
|------|----------|---------|
| 3200 | HTTP | Tempo API (queries, search, health) |
| 9095 | gRPC | Internal component communication |
| 4317 | gRPC | OTLP trace ingestion |
| 4318 | HTTP | OTLP trace ingestion |
| 14268 | HTTP | Jaeger Thrift HTTP ingestion |
| 14250 | gRPC | Jaeger gRPC ingestion |
| 6831 | UDP | Jaeger Thrift Compact |
| 6832 | UDP | Jaeger Thrift Binary |
| 9411 | HTTP | Zipkin ingestion |
| 7946 | TCP/UDP | Memberlist gossip |
