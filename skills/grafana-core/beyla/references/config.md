# Beyla configuration reference

## Full config (YAML)

```yaml
log_level: INFO

discovery:
  services:
    - name: my-app
      open_port: 8080
      # or by process name:
      # exe_path: /usr/bin/myapp
      # or by K8s metadata (auto-detected in K8s)

ebpf:
  wakeup_len: 100              # batch size for events
  track_request_headers: false # HTTP headers — high cardinality risk
  high_request_volume: false   # optimize for high-traffic services

# Distributed tracing output (OTLP)
otel_traces_export:
  endpoint: http://tempo:4318  # HTTP OTLP
  # Or gRPC:
  # endpoint: tempo:4317
  # protocol: grpc

# Metrics output (Prometheus)
prometheus_export:
  port: 9090
  path: /metrics

# Or metrics via OTLP
otel_metrics_export:
  endpoint: http://prometheus-otlp:9090
```

## Environment variables

| Variable | Description |
|----------|-------------|
| `BEYLA_OPEN_PORT` | Port(s) to instrument (e.g. `8080`, `8080-8090`) |
| `BEYLA_EXECUTABLE_NAME` | Process name pattern to instrument |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | OTLP endpoint for traces + metrics |
| `OTEL_EXPORTER_OTLP_PROTOCOL` | `grpc` or `http/protobuf` (default) |
| `OTEL_SERVICE_NAME` | Override service name in spans |
| `BEYLA_LOG_LEVEL` | `DEBUG`, `INFO`, `WARN`, `ERROR` |
| `BEYLA_PROMETHEUS_PORT` | Port for Prometheus metrics |
| `BEYLA_PROMETHEUS_PATH` | Default `/metrics` |

## Routes decorator (cardinality control)

```yaml
routes:
  patterns:
    - /user/{id}
    - /api/v1/resources/{resource_id}
  ignored_patterns:
    - /health
    - /metrics
  ignore_mode: traces       # or metrics, both
  unmatched: heuristic      # or path, wildcard, low-cardinality
```

`unmatched` strategies: `heuristic` (numeric-ID replacement, best default), `low-cardinality` (threshold collapse), `wildcard` (`/**`), `path` (real path — explosion risk).

## Trace sampling

```yaml
otel_traces_export:
  sampler:
    name: "parentbased_traceidratio"
    arg:  "0.1"             # 10% — arg is a quoted string
```

Samplers: `always_on`, `always_off`, `traceidratio`, `parentbased_always_on` (default), `parentbased_traceidratio`.

## Generated metrics

| Metric | Type | Description |
|--------|------|-------------|
| `http.server.request.duration` | Histogram | Inbound HTTP duration |
| `http.client.request.duration` | Histogram | Outbound HTTP duration |
| `rpc.server.duration` | Histogram | gRPC server duration |
| `rpc.client.duration` | Histogram | gRPC client duration |
| `db.client.operation.duration` | Histogram | DB query duration |

Labels: `http.method`, `http.route`, `http.response.status_code`, `service.name`, `service.namespace`.

## Supported runtimes

| Language | HTTP | gRPC | DB queries |
|----------|------|------|-----------|
| Go | ✅ | ✅ | ✅ |
| Java (JVM) | ✅ | ✅ | ✅ |
| Python | ✅ | ✅ | - |
| Ruby | ✅ | - | - |
| Node.js | ✅ | - | - |
| .NET | ✅ | ✅ | - |
| Rust | ✅ | ✅ | - |
| C/C++ | ✅ | - | - |
| PHP | ✅ | - | - |

## Grafana Cloud via Alloy

```yaml
otel_traces_export:  { endpoint: http://alloy:4318 }
otel_metrics_export: { endpoint: http://alloy:4318 }
```

```alloy
otelcol.receiver.otlp "beyla" {
  http { endpoint = "0.0.0.0:4318" }
  output {
    traces  = [otelcol.exporter.otlp.grafana_cloud.input]
    metrics = [otelcol.exporter.prometheus.local.input]
  }
}
```
