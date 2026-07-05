# Alloy Collection Patterns

> Canonical recipes for the common things Alloy does. Configs are taken from the official Alloy
> "Collect" docs (https://grafana.com/docs/alloy/latest/collect/) and adjusted to be runnable as-is
> with placeholder values.

## Pipeline shape, at a glance

```
discovery / receive  →  process / relabel  →  write / export
```

Every pattern below fits this shape. The label of each component (in quotes after the block type) is
your choice; references use `block.type.label.export`.

---

## 1. Prometheus metrics — scrape and remote-write

Pull `/metrics` from a static list of targets and ship to a Prometheus-compatible endpoint.

```alloy
prometheus.scrape "custom_targets" {
  targets = [
    {__address__ = "prometheus:9090"},
    {__address__ = "custom-app:80", __metrics_path__ = "/custom-metrics-path", __scheme__ = "https"},
    {__address__ = "app:12345", environment = "production"},
  ]
  forward_to      = [prometheus.remote_write.default.receiver]
  scrape_interval = "30s"
}

prometheus.remote_write "default" {
  endpoint {
    url = sys.env("PROMETHEUS_URL")
    basic_auth {
      username = sys.env("PROMETHEUS_USER")
      password = sys.env("GRAFANA_API_KEY")
    }
  }
  external_labels = {
    cluster = "prod-us-east",
    env     = "production",
  }
}
```

Notes:

- Labels beginning with `__` are stripped after relabeling; they control the scrape, not the output.
- `__scheme__` defaults to `http`, `__metrics_path__` defaults to `/metrics`.
- Add multiple `endpoint` blocks to fan-out to several backends.

## 2. Kubernetes service discovery → scrape

Scrape every pod the API server lists, filtered by relabeling.

```alloy
discovery.kubernetes "pods" {
  role = "pod"
}

discovery.relabel "pods" {
  targets = discovery.kubernetes.pods.targets

  rule {
    source_labels = ["__meta_kubernetes_pod_label_app"]
    target_label  = "app"
  }
  rule {
    source_labels = ["__meta_kubernetes_namespace"]
    target_label  = "namespace"
  }
  // Drop pods that didn't set the "app" label
  rule {
    source_labels = ["__meta_kubernetes_pod_label_app"]
    regex         = ""
    action        = "drop"
  }
}

prometheus.scrape "k8s_pods" {
  targets    = discovery.relabel.pods.output
  forward_to = [prometheus.remote_write.default.receiver]
}
```

Other `role` values for `discovery.kubernetes`: `service`, `endpoints`, `endpointslice`, `node`,
`ingress`.

## 3. Kubernetes pod logs → Loki

Tail container logs from the node Alloy is running on. Uses the standard meta-label relabeling
recommended by the docs.

```alloy
loki.write "default" {
  endpoint {
    url = sys.env("LOKI_URL")
    basic_auth {
      username = sys.env("LOKI_USER")
      password = sys.env("GRAFANA_API_KEY")
    }
  }
}

discovery.kubernetes "pod" {
  role = "pod"
  selectors {
    role  = "pod"
    field = "spec.nodeName=" + coalesce(sys.env("HOSTNAME"), constants.hostname)
  }
}

discovery.relabel "pod_logs" {
  targets = discovery.kubernetes.pod.targets

  rule { source_labels = ["__meta_kubernetes_namespace"]                  target_label = "namespace"  action = "replace" }
  rule { source_labels = ["__meta_kubernetes_pod_name"]                   target_label = "pod"        action = "replace" }
  rule { source_labels = ["__meta_kubernetes_pod_container_name"]         target_label = "container"  action = "replace" }
  rule { source_labels = ["__meta_kubernetes_pod_label_app_kubernetes_io_name"] target_label = "app"  action = "replace" }

  rule {
    source_labels = ["__meta_kubernetes_namespace", "__meta_kubernetes_pod_container_name"]
    target_label  = "job"
    separator     = "/"
    replacement   = "$1"
    action        = "replace"
  }

  rule {
    source_labels = ["__meta_kubernetes_pod_uid", "__meta_kubernetes_pod_container_name"]
    target_label  = "__path__"
    separator     = "/"
    replacement   = "/var/log/pods/*$1/*.log"
    action        = "replace"
  }
}

loki.source.kubernetes "pod_logs" {
  targets    = discovery.relabel.pod_logs.output
  forward_to = [loki.process.pod_logs.receiver]
}

loki.process "pod_logs" {
  forward_to = [loki.write.default.receiver]
  stage.static_labels {
    values = { cluster = "prod-us-east" }
  }
}
```

## 4. Kubernetes cluster events → Loki

```alloy
loki.source.kubernetes_events "cluster_events" {
  job_name   = "integrations/kubernetes/eventhandler"
  log_format = "logfmt"
  forward_to = [loki.process.cluster_events.receiver]
}

loki.process "cluster_events" {
  forward_to = [loki.write.default.receiver]
  stage.static_labels {
    values = { cluster = "prod-us-east" }
  }
  stage.labels {
    values = { kubernetes_cluster_events = "job" }
  }
}
```

## 5. Node/system logs → Loki

```alloy
local.file_match "node_logs" {
  path_targets = [{
    __path__  = "/var/log/syslog",
    job       = "node/syslog",
    node_name = sys.env("HOSTNAME"),
    cluster   = "prod-us-east",
  }]
}

loki.source.file "node_logs" {
  targets    = local.file_match.node_logs.targets
  forward_to = [loki.write.default.receiver]
}
```

## 6. systemd journal → Loki

```alloy
loki.source.journal "system" {
  forward_to = [loki.write.default.receiver]
  labels     = { job = "systemd-journal" }
  // optional: relabel_rules, matches, format_as_json
}
```

## 7. OpenTelemetry → Grafana LGTM stack

OTLP in, split to metrics/logs/traces with a batch processor, ship to Grafana Cloud.

```alloy
otelcol.receiver.otlp "default" {
  grpc { endpoint = "0.0.0.0:4317" }
  http { endpoint = "0.0.0.0:4318" }

  output {
    metrics = [otelcol.processor.batch.default.input]
    logs    = [otelcol.processor.batch.default.input]
    traces  = [otelcol.processor.batch.default.input]
  }
}

otelcol.processor.batch "default" {
  output {
    metrics = [otelcol.exporter.prometheus.grafana_cloud_metrics.input]
    logs    = [otelcol.exporter.loki.grafana_cloud_logs.input]
    traces  = [otelcol.exporter.otlphttp.grafana_cloud_traces.input]
  }
}

otelcol.exporter.otlphttp "grafana_cloud_traces" {
  client {
    endpoint = "https://tempo-us-central1.grafana.net:443"
    auth     = otelcol.auth.basic.grafana_cloud.handler
  }
}

otelcol.exporter.prometheus "grafana_cloud_metrics" {
  forward_to = [prometheus.remote_write.grafana_cloud.receiver]
}

otelcol.exporter.loki "grafana_cloud_logs" {
  forward_to = [loki.write.grafana_cloud.receiver]
}

otelcol.auth.basic "grafana_cloud" {
  username = sys.env("GRAFANA_CLOUD_INSTANCE_ID")
  password = sys.env("GRAFANA_CLOUD_API_KEY")
}

prometheus.remote_write "grafana_cloud" {
  endpoint {
    url = "https://prometheus-us-central1.grafana.net/api/prom/push"
    basic_auth {
      username = sys.env("GRAFANA_CLOUD_METRICS_USER")
      password = sys.env("GRAFANA_CLOUD_API_KEY")
    }
  }
}

loki.write "grafana_cloud" {
  endpoint {
    url = "https://logs-prod-us-central1.grafana.net/loki/api/v1/push"
    basic_auth {
      username = sys.env("GRAFANA_CLOUD_LOGS_USER")
      password = sys.env("GRAFANA_CLOUD_API_KEY")
    }
  }
}
```

Add a `memory_limiter` in front of `batch` in production:

```alloy
otelcol.processor.memory_limiter "default" {
  check_interval   = "1s"
  limit_percentage = 80
  output {
    metrics = [otelcol.processor.batch.default.input]
    logs    = [otelcol.processor.batch.default.input]
    traces  = [otelcol.processor.batch.default.input]
  }
}
```

…and point the OTLP receiver's `output.*` at `otelcol.processor.memory_limiter.default.input`.

## 8. Profiles — pprof scraping → Pyroscope

```alloy
pyroscope.scrape "default" {
  targets = [
    {__address__ = "localhost:6060", service_name = "myapp"},
  ]
  forward_to = [pyroscope.write.default.receiver]
}

pyroscope.write "default" {
  endpoint {
    url = sys.env("PYROSCOPE_URL")
    basic_auth {
      username = sys.env("PYROSCOPE_USER")
      password = sys.env("GRAFANA_API_KEY")
    }
  }
}
```

## 9. Zero-code traces and metrics with Beyla

```alloy
beyla.ebpf "default" {
  open_port = "8080"   // or attach_pid, executable_name, k8s selectors

  output {
    metrics = [otelcol.processor.batch.default.input]
    traces  = [otelcol.processor.batch.default.input]
  }
}
```

## 10. Frontend telemetry — Faro

```alloy
faro.receiver "default" {
  server {
    listen_address = "0.0.0.0"
    listen_port    = 12347
    // Replace with your actual web origins before deploying — wildcard "*" lets any site send
    // telemetry to this endpoint and is not suitable for production.
    cors_allowed_origins = ["https://app.example.com"]
  }

  output {
    logs   = [loki.write.grafana_cloud.receiver]
    traces = [otelcol.processor.batch.default.input]
  }
}
```

## 11. Clustering — distribute scrape load

Run multiple Alloy replicas and let them shard targets among themselves.

```alloy
clustering {
  enabled = true
}

prometheus.scrape "cluster_aware" {
  targets    = discovery.kubernetes.pods.targets
  forward_to = [prometheus.remote_write.default.receiver]
  clustering { enabled = true }
}
```

Cluster discovery uses memberlist; configure peer addresses via the `--cluster.*` CLI flags on
`alloy run` (e.g. `--cluster.join-addresses=alloy-headless:12345`).

## 12. Fleet Management — remote config

```alloy
remotecfg {
  url = "https://fleet-management-prod-XXX.grafana.net"
  basic_auth {
    username = sys.env("FM_USERNAME")
    password = sys.env("FM_TOKEN")
  }
  poll_interval = "1m"
}
```

With `remotecfg`, the local file becomes the bootstrap. The fleet server delivers the rest as
modules Alloy imports automatically.

## 13. Modules and imports

Pull components from a Git module library:

```alloy
import.git "k8s_monitoring" {
  repository = "https://github.com/grafana/alloy-modules"
  revision   = "main"
  path       = "modules/kubernetes/"
}

k8s_monitoring.pods "default" {
  forward_to = [prometheus.remote_write.default.receiver]
}
```

## 14. Pipeline processing — relabel and parse

Drop noisy Go metrics, add an `environment` label:

```alloy
prometheus.relabel "filter" {
  forward_to = [prometheus.remote_write.default.receiver]

  rule {
    source_labels = ["__name__"]
    regex         = "go_.*"
    action        = "drop"
  }
  rule {
    target_label = "environment"
    replacement  = "production"
  }
}
```

Parse JSON logs and lift one field to a label:

```alloy
loki.process "json_parse" {
  forward_to = [loki.write.default.receiver]

  stage.json {
    expressions = { level = "level", msg = "message" }
  }
  stage.labels {
    values = { level = "" }
  }
  stage.drop {
    expression = ".*health check.*"
  }
}
```

---

## Running Alloy

```bash
alloy run /etc/alloy/config.alloy \
  --server.http.listen-addr=0.0.0.0:12345 \
  --storage.path=/var/lib/alloy/data \
  --cluster.enabled=true \
  --cluster.join-addresses=alloy-headless.alloy.svc:12345
```

Reload after editing: `kill -HUP <pid>` or `curl -XPOST http://localhost:12345/-/reload`.

UI and component graph: `http://localhost:12345/`.
