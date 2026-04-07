---
name: tempo
license: Apache-2.0
description: >
  Grafana Tempo distributed tracing overview including TraceQL, service graphs, drilldown capabilities
  (trace-to-logs, trace-to-metrics, trace-to-profiles, exemplars), and OpenTelemetry integration.
  Use when working with Tempo, writing TraceQL queries, configuring trace correlations, or discussing
  distributed tracing architecture and best practices.
---

# Distributed Tracing with Grafana Tempo

## Value Proposition

Cost-efficient, high-scale distributed tracing backend with end-to-end visibility into request flows.
Zero-index architecture makes 100% trace sampling economically viable while enabling seamless correlation
between traces, metrics, logs, and profiles.

**Key Differentiators**: Zero-index storage, TraceQL query language, native OTLP support, exemplars
integration, automatic service graph generation.

## TraceQL Quick Reference

### Basic Queries

```traceql
# Find spans from a service
{ resource.service.name = "checkout" }

# Slow requests
{ duration > 5s }

# Errors
{ status = error }

# HTTP errors
{ span.http.status_code >= 500 }

# Combined
{ resource.service.name = "api" && duration > 1s && status = error }

# Regex
{ span.http.url =~ "/api/v2/.*" }
```

### Structural Queries

```traceql
# Frontend with downstream errors
{ resource.service.name = "frontend" } >> { status = error }

# Service A calls service B
{ resource.service.name = "A" } > { resource.service.name = "B" }
```

### Aggregations

```traceql
# Traces with >10 DB calls
{ span.db.system = "postgresql" } | count() > 10

# Average DB call > 10ms
{ span.db.system = "postgresql" } | avg(duration) > 10ms

# Group by service, count errors
{ status = error } | by(resource.service.name) | count() > 5
```

## Drilldown Capabilities

### Trace-to-Logs

Clickable links from spans to Loki log entries via trace/span ID correlation.

```yaml
jsonData:
  tracesToLogs:
    datasourceUid: "loki-uid"
    spanStartTimeShift: "-5s"
    spanEndTimeShift: "+1m"
    filterByTraceID: true
    tags:
      - key: "service.name"
        value: "service"
```

### Trace-to-Metrics

Links spans to Prometheus metric time series for resource correlation.

```yaml
jsonData:
  tracesToMetrics:
    datasourceUid: "prometheus-uid"
    tags:
      - key: "service.name"
        value: "service"
    queries:
      - name: "Request Rate"
        query: "rate(requests_total{${__tags}}[5m])"
      - name: "Error Rate"
        query: 'rate(requests_total{${__tags},status=~"5.."}[5m])'
```

### Trace-to-Profiles

Connects spans to Pyroscope profiling data for CPU/memory analysis.

```yaml
jsonData:
  tracesToProfiles:
    datasourceUid: "pyroscope-uid"
    tags:
      - key: "service.name"
        value: "service_name"
    profileTypeId: "process_cpu:cpu:nanoseconds:cpu:nanoseconds"
```

### Exemplars (Metrics-to-Traces)

Trace IDs stored alongside metric samples enable jumping from metric graphs to specific traces.
Tempo's metrics-generator creates exemplars automatically. Stars on time series panels link to traces.

## Service Graphs

Tempo's metrics-generator derives RED metrics (Rate, Error, Duration) from traces automatically.

**Generated metrics**:
- `traces_service_graph_request_total{client, server}` — request count
- `traces_service_graph_request_failed_total` — failed requests
- `traces_service_graph_request_server_seconds` — duration histogram
- `traces_spanmetrics_calls_total{service, span_name}` — span count
- `traces_spanmetrics_duration_seconds` — span duration histogram

## OpenTelemetry Semantic Conventions

| Category | Key Attributes |
|----------|---------------|
| **HTTP** | `http.method`, `http.status_code`, `http.url`, `http.route` |
| **Database** | `db.system`, `db.name`, `db.statement`, `db.operation` |
| **Service** | `service.name`, `service.namespace`, `service.version` |
| **K8s** | `k8s.namespace.name`, `k8s.pod.name`, `k8s.deployment.name` |

## Architecture

- **Distributor**: Accepts spans (OTLP, Jaeger, Zipkin), routes to ingesters
- **Ingester**: Indexes and stores spans, flushes Parquet blocks to object storage
- **Metrics-Generator**: Derives RED metrics, service graphs, exemplars
- **Querier**: Queries ingesters + object storage, uses bloom filters
- **Compactor**: Compresses, deduplicates, enforces retention

## Best Practices

- **Instrumentation**: Create spans for work > 1ms, use semantic conventions, limit attributes
- **Sampling**: Start with 100% if costs allow; use tail-based sampling to keep all errors
- **Query performance**: Use scoped attributes (`resource.service.name` vs `.service.name`)
- **Auto-instrumentation**: Start with Grafana Beyla (eBPF) or OTel auto-instrumentation, add manual spans for business logic

## Resources

- [Tempo Docs](https://grafana.com/docs/tempo/latest/)
- [TraceQL Reference](https://grafana.com/docs/tempo/latest/traceql/)
- [Traces Drilldown App](https://github.com/grafana/traces-drilldown)
- [Service Graphs](https://grafana.com/docs/tempo/latest/metrics-generator/service_graphs/)
- [Grafana Beyla](https://grafana.com/docs/beyla/)
- [OpenTelemetry Docs](https://opentelemetry.io/docs/)
