---
name: tempo
license: Apache-2.0
description: Stand up Grafana Tempo as a cost-efficient distributed-tracing backend that only needs object storage, and write TraceQL queries against it. Covers OTLP + Jaeger + Zipkin ingestion, the distributor → live-store → block-builder → object-storage write path, metrics-generator for RED spanmetrics + service graphs, Helm `tempo-distributed` deployment, multi-tenant `X-Scope-OrgID`, TraceQL span / resource / event scopes, structural operators (`>>`, `<<`), `rate()` + `quantile_over_time` metrics, and the traces-to-logs / metrics / profiles datasource links. Use when deploying Tempo, writing a TraceQL query for slow / errored requests, debugging "no traces showing in Explore", sizing queriers / compactors, configuring S3 / GCS / Azure block storage, or wiring trace ↔ log ↔ profile correlation — even when the user says "tracing backend", "find slow requests", "show me the service graph", "store traces in S3", "Jaeger compatible store", or "what called this span" without naming Tempo.
---

# Grafana Tempo

> **Docs**: https://grafana.com/docs/tempo/latest/

Cost-efficient distributed tracing. Accepts OTLP / Jaeger / Zipkin / OpenCensus / Kafka. Stores Parquet blocks in S3/GCS/Azure.

## Prerequisites

- Docker (quick start) or Kubernetes (production)
- Object storage bucket (S3/GCS/Azure) for distributed deployments
- An OTLP-emitting app or `tempo-cli` for synthetic traffic
- A Grafana stack with a Tempo datasource for querying

## Common Workflows

### 1. Stand up Tempo locally + verify ingestion

```bash
# 1. Start the official Docker Compose example
git clone https://github.com/grafana/tempo.git
cd tempo/example/docker-compose/local
mkdir -p tempo-data
docker compose up -d

# 2. Verify readiness
curl -sf http://localhost:3200/ready                              # → "ready"

# 3. Send a synthetic OTLP span (full payload in scratch terminal)
curl -X POST -H 'Content-Type: application/json' \
  http://localhost:4318/v1/traces \
  -d '{"resourceSpans":[{"resource":{"attributes":[{"key":"service.name","value":{"stringValue":"my-service"}}]},
       "scopeSpans":[{"spans":[{"traceId":"5B8EFFF798038103D269B633813FC700","spanId":"EEE19B7EC3C1B100",
       "name":"my-op","startTimeUnixNano":1689969302000000000,"endTimeUnixNano":1689969302500000000,"kind":2}]}]}]}'

# 4. Verify the trace landed (ingestion-counter > 0 and the trace is fetchable)
curl -s http://localhost:3200/metrics | grep tempo_distributor_spans_received_total | head
curl -s http://localhost:3200/api/v2/traces/5B8EFFF798038103D269B633813FC700 | jq '.batches | length'
# Expect > 0.

# 5. In Grafana → Explore → Tempo, run TraceQL: {resource.service.name="my-service"}
```

### 2. Send traces from an app via Alloy

```alloy
// alloy.river
otelcol.receiver.otlp "default" {
  grpc { endpoint = "0.0.0.0:4317" }
  http { endpoint = "0.0.0.0:4318" }
  output { traces = [otelcol.exporter.otlp.tempo.input] }
}

otelcol.exporter.otlp "tempo" {
  client {
    endpoint = "tempo:4317"
    tls { insecure = true }
  }
}
```

```bash
# Verify Alloy forwarded successfully
curl -s http://localhost:12345/metrics | grep otelcol_exporter_sent_spans
# Then: same Grafana → Explore → Tempo check.
```

### 3. Write + run TraceQL

```traceql
# Slow requests from a service
{ resource.service.name = "frontend" && duration > 1s }

# Server span that has a downstream error (structural)
{ kind = server } >> { status = error }

# Error rate per service (metrics)
{ status = error } | rate() by (resource.service.name)
```

Full operator + scope cheat sheet, intrinsics list, metric functions: [`references/traceql.md`](references/traceql.md).

```bash
# Via the API
curl -sG --data-urlencode 'q={resource.service.name="frontend" && duration > 1s}' \
  --data-urlencode "start=$(date -d '1h ago' +%s)" --data-urlencode "end=$(date +%s)" \
  http://localhost:3200/api/search | jq '.traces | length'
```

### 4. Deploy on Kubernetes (Helm)

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm install tempo grafana/tempo-distributed --version 1.61.3 \
  --set storage.trace.backend=s3 \
  --set storage.trace.s3.bucket=my-tempo-bucket \
  --set storage.trace.s3.region=us-east-1

# Verify every pod is Ready (distributor, ingester, querier, query-frontend, compactor)
kubectl get pods -n default -l app.kubernetes.io/instance=tempo
kubectl port-forward svc/tempo-query-frontend 3200:3200 &
curl -sf http://localhost:3200/ready
```

## Multi-tenancy

```yaml
multitenancy_enabled: true
# All requests must include header: X-Scope-OrgID: <tenant-id>
```

Full architecture, ports, performance tuning, metrics-generator config, multi-tenant client snippets, traces-to-logs/metrics/profiles datasource: [`references/architecture-and-operations.md`](references/architecture-and-operations.md).

## Troubleshooting

- `/ready` → 503 → ingester still joining; check `tempo_ingester_*` metrics + logs
- 429 on push → raise `max_outstanding_per_tenant` or per-tenant ingest limits
- "no traces showing in Explore" → confirm `X-Scope-OrgID` matches between writer and Grafana datasource
- TraceQL slow → narrow `start`/`end`, add a service.name filter, enable dedicated Parquet columns for hot attributes

## Resources

- [Tempo docs](https://grafana.com/docs/tempo/latest/)
- [TraceQL reference](https://grafana.com/docs/tempo/latest/traceql/)
- [`references/traceql.md`](references/traceql.md) — full TraceQL cheat sheet
- [`references/architecture-and-operations.md`](references/architecture-and-operations.md) — components, ports, Helm, tuning, datasource links
