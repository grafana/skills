---
name: beyla
license: Apache-2.0
description: >
  Grafana Beyla eBPF auto-instrumentation for application observability without code changes.
  Covers supported languages/runtimes, requirements, installation, configuration (discovery, eBPF settings,
  OTLP traces export, Prometheus metrics export), Kubernetes deployment, and integration with Grafana
  Cloud. Use when setting up zero-code instrumentation, configuring eBPF probes, deploying Beyla to
  Kubernetes, connecting to Tempo/Prometheus, or troubleshooting instrumentation issues.
---

# Grafana Beyla

> **Docs**: https://grafana.com/docs/beyla/latest/

Beyla is a Grafana eBPF auto-instrumentation tool that captures HTTP/gRPC traffic and generates traces
and metrics **without modifying application code**.

## Requirements

- **Linux kernel**: 5.8+ with BTF (BPF Type Format) enabled
- **Privileges**: root or `CAP_SYS_ADMIN`; in Kubernetes must run in host PID namespace
- **Architectures**: x86_64, ARM64

Check BTF support:
```bash
ls /sys/kernel/btf/vmlinux  # must exist
```

## Supported Languages / Runtimes

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

## Installation

```bash
# Docker
docker run --privileged --pid=host \
  -v /sys/kernel/debug:/sys/kernel/debug:ro \
  -e BEYLA_OPEN_PORT=8080 \
  -e OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4318 \
  grafana/beyla

# Kubernetes (Helm)
helm repo add grafana https://grafana.github.io/helm-charts
helm install beyla grafana/beyla \
  --set discovery.services[0].open_port=8080 \
  --set otelTraces.endpoint=http://tempo:4318
```

## Configuration File

```yaml
# beyla-config.yml
log_level: INFO

discovery:
  services:
    - name: my-app
      open_port: 8080
      # or by process name:
      # exe_path: /usr/bin/myapp
      # or by K8s pod metadata (auto-detected in K8s)

ebpf:
  wakeup_len: 100           # batch size for events
  track_request_headers: false  # enable to capture HTTP headers (high cardinality risk)
  high_request_volume: false    # optimize for high-traffic services

# Distributed tracing output (OTLP)
otel_traces_export:
  endpoint: http://tempo:4318  # HTTP OTLP endpoint
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

## Kubernetes Deployment

### DaemonSet (recommended for cluster-wide)

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: beyla
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app: beyla
  template:
    metadata:
      labels:
        app: beyla
    spec:
      hostPID: true          # required for eBPF
      serviceAccountName: beyla
      containers:
        - name: beyla
          image: grafana/beyla:latest
          securityContext:
            privileged: true   # or use specific capabilities
            # Alternative (non-privileged):
            # capabilities:
            #   add: [SYS_ADMIN, SYS_PTRACE, NET_ADMIN]
          env:
            - name: BEYLA_OPEN_PORT
              value: "8080"
            - name: OTEL_EXPORTER_OTLP_ENDPOINT
              value: "http://alloy:4318"
          volumeMounts:
            - name: sys-kernel-debug
              mountPath: /sys/kernel/debug
              readOnly: true
      volumes:
        - name: sys-kernel-debug
          hostPath:
            path: /sys/kernel/debug
```

### Network Policies and RBAC

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: beyla
  namespace: monitoring
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: beyla
rules:
  - apiGroups: [""]
    resources: [nodes, pods, services, endpoints, namespaces]
    verbs: [get, list, watch]
```

## Environment Variables

| Variable | Description |
|----------|-------------|
| `BEYLA_OPEN_PORT` | Port(s) to instrument (e.g., `8080`, `8080-8090`) |
| `BEYLA_EXECUTABLE_NAME` | Process name pattern to instrument |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | OTLP endpoint for traces and metrics |
| `OTEL_EXPORTER_OTLP_PROTOCOL` | `grpc` or `http/protobuf` (default) |
| `OTEL_SERVICE_NAME` | Override service name in spans |
| `BEYLA_LOG_LEVEL` | `DEBUG`, `INFO`, `WARN`, `ERROR` |
| `BEYLA_PROMETHEUS_PORT` | Port for Prometheus metrics scrape |
| `BEYLA_PROMETHEUS_PATH` | Path for Prometheus metrics (default `/metrics`) |

## Grafana Cloud Integration

```yaml
# Using Alloy as the OTLP receiver
otel_traces_export:
  endpoint: http://alloy:4318   # Alloy forwards to Grafana Cloud Tempo

otel_metrics_export:
  endpoint: http://alloy:4318   # Alloy forwards to Grafana Cloud Prometheus
```

Via Alloy config:
```alloy
otelcol.receiver.otlp "beyla" {
  http { endpoint = "0.0.0.0:4318" }
  output {
    traces  = [otelcol.exporter.otlp.grafana_cloud.input]
    metrics = [otelcol.exporter.prometheus.local.input]
  }
}
```

## Routes Decorator (Cardinality Control)

**Critical for production** — prevents HTTP path cardinality explosion:

```yaml
routes:
  patterns:
    - /user/{id}
    - /api/v1/resources/{resource_id}
  ignored_patterns:
    - /health
    - /metrics
  ignore_mode: traces    # or: metrics, both
  unmatched: heuristic   # or: path, wildcard, low-cardinality
```

`unmatched` strategies: `heuristic` (replaces numeric IDs, best default), `low-cardinality` (threshold-based collapsing), `wildcard` (`/**`), `path` (actual path — risk of explosion).

## Trace Sampling

```yaml
otel_traces_export:
  sampler:
    name: "parentbased_traceidratio"  # parent-aware fraction sampling
    arg: "0.1"    # 10% sampling — arg is a quoted string
```

Samplers: `always_on`, `always_off`, `traceidratio`, `parentbased_always_on` (default), `parentbased_traceidratio`.

## Generated Metrics

| Metric | Type | Description |
|--------|------|-------------|
| `http.server.request.duration` | Histogram | Inbound HTTP request duration |
| `http.client.request.duration` | Histogram | Outbound HTTP request duration |
| `rpc.server.duration` | Histogram | gRPC server call duration |
| `rpc.client.duration` | Histogram | gRPC client call duration |
| `db.client.operation.duration` | Histogram | DB query duration |

Labels: `http.method`, `http.route`, `http.response.status_code`, `service.name`, `service.namespace`

## Kubernetes Auto-Discovery

In Kubernetes, Beyla auto-discovers pods and enriches telemetry with K8s metadata:

```yaml
discovery:
  services:
    - k8s_namespace: "production"     # instrument all pods in namespace
    - k8s_pod_name: "frontend.*"      # by pod name regex
    - k8s_deployment_name: "api"      # by deployment name
    - open_port: 8080                 # or by port (any pod)
```

Auto-enriched span attributes: `k8s.namespace.name`, `k8s.pod.name`, `k8s.node.name`, `k8s.deployment.name`
