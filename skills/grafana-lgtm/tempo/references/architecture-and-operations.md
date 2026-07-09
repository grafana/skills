# Architecture, deployment, performance

## Component map

```
Applications
   |
   v   (OTLP 4317/4318, Jaeger 14250/14268, Zipkin 9411)
[Distributor]  →  [Kafka]  →  [Live Stores]   (recent)
                            →  [Block Builders] (Parquet → object storage)
                            →  [Metrics Generator] (RED metrics → Prometheus)

Grafana → [Query Frontend] → [Querier pool] → Live Stores + Object Storage
```

| Component | Role | Default Port |
|-----------|------|--------------|
| Distributor | Receives spans, routes by traceID hash | 4317 (gRPC), 4318 (HTTP) |
| Live Store | Buffers recent data on local disk | - |
| Query Frontend | Query orchestrator + sharding | 3200 (HTTP) |
| Querier | Executes search against storage | - |
| Compactor | Merges blocks + retention | - |
| Block Builder | Final Parquet blocks → object storage | - |
| Metrics Generator | RED metrics from spans | - |

## Deployment

### Docker Compose quick start

```bash
git clone https://github.com/grafana/tempo.git
cd tempo/example/docker-compose/local
mkdir tempo-data
docker compose up -d
# Grafana → http://localhost:3000  |  Tempo API → http://localhost:3200
```

### Kubernetes (Helm `tempo-distributed`)

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm install tempo grafana/tempo-distributed --version 1.61.3 \
  --set storage.trace.backend=s3 \
  --set storage.trace.s3.bucket=my-tempo-bucket \
  --set storage.trace.s3.region=us-east-1
```

## Multi-tenancy

```yaml
multitenancy_enabled: true
# All requests need X-Scope-OrgID: <tenant-id>
```

OTel Collector header:

```yaml
exporters:
  otlp:
    headers:
      x-scope-orgid: tenant-id
```

Grafana datasource:

```yaml
jsonData:
  httpHeaderName1: "X-Scope-OrgID"
secureJsonData:
  httpHeaderValue1: "tenant-id"
```

## Ports

| Port | Protocol | Purpose |
|------|----------|---------|
| 3200 | HTTP | Tempo API (queries, search, health) |
| 9095 | gRPC | Internal component communication |
| 4317 | gRPC | OTLP trace ingestion |
| 4318 | HTTP | OTLP trace ingestion |
| 14268 | HTTP | Jaeger Thrift HTTP |
| 14250 | gRPC | Jaeger gRPC |
| 6831 / 6832 | UDP | Jaeger Thrift Compact / Binary |
| 9411 | HTTP | Zipkin ingestion |
| 7946 | TCP/UDP | Memberlist gossip |

## Performance tuning

| Problem | Solution |
|---------|----------|
| Slow searches | Scale queriers; scale compactors to reduce block count |
| High querier memory | Reduce `max_concurrent_queries`; lower `target_bytes_per_job` |
| High ingester memory | Reduce `max_block_bytes`; lower per-tenant trace limits |
| Slow attribute queries | Add dedicated Parquet columns for frequent attributes |
| Cache miss high | Increase cache size; tune `cache_min_compaction_level` |
| 429 rate-limited | Raise `max_outstanding_per_tenant` or per-tenant ingest limits |
| Memcached errors | Increase memcached conns (`-c 4096`) |

## Best-practice notes

- Replication factor 3 in prod for HA
- Object storage required for distributed deployments
- Enable dedicated attribute columns for most-queried attributes
- Set block retention per-tenant via `overrides`
- Watch `tempo_ingester_live_traces` for ingester pressure
- Follow OpenTelemetry semantic conventions (`span.*`, `resource.*`)
- ~128 attrs/span max; use span linking for batch processing

## Metrics from traces

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
      processors: [service-graphs, span-metrics]
```

Processors:

- **Service Graphs** → `traces_service_graph_request_total`, `traces_service_graph_request_failed_total`, duration histograms
- **Span Metrics** (RED) → `traces_spanmetrics_calls_total`, `traces_spanmetrics_duration_seconds_*` with service / span_name / span_kind / status_code
- **Local Blocks** → enables TraceQL metrics queries on recent data

## Grafana datasource (traces-to-logs/metrics/profiles)

```yaml
datasources:
  - name: Tempo
    type: tempo
    url: http://tempo:3200
    jsonData:
      tracesToLogsV2:
        datasourceUid: loki-uid
        filterByTraceID: true
        tags: [{key: "service.name", value: "app"}]
      tracesToMetrics:
        datasourceUid: prometheus-uid
        tags: [{key: "service.name", value: "service"}]
        queries:
          - name: Error Rate
            query: 'sum(rate(traces_spanmetrics_calls_total{$$__tags, status_code="STATUS_CODE_ERROR"}[5m]))'
      tracesToProfiles:
        datasourceUid: pyroscope-uid
        tags: [{key: "service.name", value: "service_name"}]
      serviceMap:
        datasourceUid: prometheus-uid
```

## HTTP API

```bash
# Search
GET /api/search?q={status=error}&limit=20&start=<unix>&end=<unix>

# Trace by ID
GET /api/traces/<traceID>
GET /api/v2/traces/<traceID>

# Tags
GET /api/search/tags
GET /api/search/tag/service.name/values

# TraceQL metrics
GET /api/metrics/query_range?q={status=error}|rate()&start=...&end=...&step=60

# Health
GET /ready
```
