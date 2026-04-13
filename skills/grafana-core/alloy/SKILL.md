---
name: alloy
license: Apache-2.0
description: >
  Grafana Alloy OpenTelemetry collector and telemetry pipeline configuration. Covers the Alloy configuration
  language (blocks, attributes, expressions), components for collecting metrics/logs/traces/profiles,
  sending data to Grafana Cloud/Prometheus/Loki/Tempo, clustering, Fleet Management remote config, and
  building telemetry pipelines. Use when configuring Alloy, writing Alloy config files (.alloy),
  building data collection pipelines, setting up scraping, or troubleshooting Alloy deployments.
---

# Grafana Alloy

> **Docs**: https://grafana.com/docs/alloy/latest/

Alloy is an open-source OpenTelemetry collector distribution that unifies telemetry collection (metrics, logs, traces, profiles) in a single binary supporting Prometheus and OTel standards.

## Installation

```bash
# macOS
brew install grafana/grafana/alloy

# Linux (Debian/Ubuntu)
sudo apt install alloy

# Docker
docker run -v $(pwd)/config.alloy:/etc/alloy/config.alloy \
  grafana/alloy:latest run /etc/alloy/config.alloy

# Kubernetes (Helm)
helm repo add grafana https://grafana.github.io/helm-charts
helm install alloy grafana/alloy -f values.yaml

# Run
alloy run /path/to/config.alloy
```

**Default config paths:**
- Linux: `/etc/alloy/config.alloy`
- macOS: `$(brew --prefix)/etc/alloy/config.alloy`
- Windows: `%ProgramFiles%\GrafanaLabs\Alloy\config.alloy`

## Config Language Syntax

Config files use `.alloy` extension (UTF-8). See `references/config-syntax.md` for full reference.

```alloy
// Block syntax: BLOCK_TYPE "LABEL" { ... }
prometheus.scrape "my_scraper" {
  targets    = [{"__address__" = "localhost:9090"}]
  forward_to = [prometheus.remote_write.cloud.receiver]
}

// Attribute: NAME = VALUE
scrape_interval = "30s"

// Reference another component's export
forward_to = [prometheus.remote_write.cloud.receiver]

// Environment variable
password = sys.env("GRAFANA_API_KEY")

// String concat
url = "https://" + sys.env("HOST")
```

## Core Component Patterns

See `references/components.md` for full component reference.

### Metrics: Scrape → Remote Write

```alloy
prometheus.scrape "app" {
  targets    = discovery.kubernetes.pods.targets
  forward_to = [prometheus.remote_write.cloud.receiver]
  scrape_interval = "30s"
}

prometheus.remote_write "cloud" {
  endpoint {
    url = "https://prometheus-xxx.grafana.net/api/prom/push"
    basic_auth {
      username = sys.env("PROM_USER")
      password = sys.env("GRAFANA_API_KEY")
    }
  }
}
```

### Logs: File → Loki

```alloy
loki.source.file "app_logs" {
  targets = [
    {__path__ = "/var/log/app/*.log",   job = "app"},
    {__path__ = "/var/log/nginx/*.log", job = "nginx"},
  ]
  forward_to = [loki.write.cloud.receiver]
}

loki.write "cloud" {
  endpoint {
    url = "https://logs-xxx.grafana.net/loki/api/v1/push"
    basic_auth {
      username = sys.env("LOKI_USER")
      password = sys.env("GRAFANA_API_KEY")
    }
  }
}
```

### Traces: OTLP Receive → Export

```alloy
otelcol.receiver.otlp "default" {
  grpc { endpoint = "0.0.0.0:4317" }
  http { endpoint = "0.0.0.0:4318" }
  output {
    traces  = [otelcol.exporter.otlp.tempo.input]
    metrics = [otelcol.exporter.prometheus.local.input]
    logs    = [otelcol.exporter.loki.cloud.input]
  }
}

otelcol.exporter.otlp "tempo" {
  client {
    endpoint = "tempo-xxx.grafana.net/tempo:443"
    auth     = otelcol.auth.basic.grafana_cloud.handler
  }
}

otelcol.auth.basic "grafana_cloud" {
  username = sys.env("TEMPO_USER")
  password = sys.env("GRAFANA_API_KEY")
}
```

### Kubernetes Discovery

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
  // Drop pods without app label
  rule {
    source_labels = ["__meta_kubernetes_pod_label_app"]
    regex         = ""
    action        = "drop"
  }
}

prometheus.scrape "kubernetes" {
  targets    = discovery.relabel.pods.output
  forward_to = [prometheus.remote_write.cloud.receiver]
}
```

## Configuration Blocks (top-level)

```alloy
logging {
  level  = "info"   // debug, info, warn, error
  format = "logfmt" // logfmt, json
}

http {
  listen_addr = "0.0.0.0:12345"  // UI at http://localhost:12345
}

// Fleet Management remote config
remotecfg {
  url = "https://fleet-management.grafana.net"
  basic_auth {
    username = sys.env("FM_USERNAME")
    password = sys.env("FM_TOKEN")
  }
  poll_interval = "1m"
}

tracing {
  sampling_fraction = 0.1
  write_to = [otelcol.exporter.otlp.default.input]
}
```

## Modules and Imports

```alloy
// Import from local file
import.file "utils" {
  filename = "./modules/utils.alloy"
}

// Import from Git
import.git "k8s_monitoring" {
  repository = "https://github.com/grafana/alloy-modules"
  revision   = "main"
  path       = "modules/kubernetes/"
}

// Import from HTTP
import.http "shared" {
  url            = "https://config-server/alloy/shared.alloy"
  poll_frequency = "5m"
}

// Use imported component
utils.my_component "example" {
  arg = "value"
}
```

## Clustering

```alloy
clustering {
  enabled = true
}

prometheus.scrape "cluster_aware" {
  targets    = discovery.kubernetes.pods.targets
  forward_to = [prometheus.remote_write.cloud.receiver]
  clustering { enabled = true }  // distributes scrape targets across cluster nodes
}
```

## Processing: Relabeling and Transformation

```alloy
// Relabel metrics
prometheus.relabel "filter" {
  forward_to = [prometheus.remote_write.cloud.receiver]
  rule {
    source_labels = ["__name__"]
    regex         = "go_.*"
    action        = "drop"
  }
  rule {
    source_labels = ["env"]
    replacement   = "production"
    target_label  = "environment"
  }
}

// Loki pipeline processing
loki.process "parse" {
  forward_to = [loki.write.cloud.receiver]
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

## Key Components Quick Reference

| Component | Purpose |
|-----------|---------|
| `prometheus.scrape` | Scrape Prometheus metrics endpoints |
| `prometheus.remote_write` | Send metrics via remote write |
| `prometheus.relabel` | Relabel/filter metrics |
| `loki.source.file` | Read logs from files |
| `loki.source.kubernetes` | Read Kubernetes pod logs |
| `loki.write` | Send logs to Loki |
| `loki.process` | Process/transform logs (pipeline stages) |
| `otelcol.receiver.otlp` | Receive OTLP data (gRPC/HTTP) |
| `otelcol.exporter.otlp` | Export via OTLP gRPC |
| `otelcol.exporter.otlphttp` | Export via OTLP HTTP |
| `otelcol.processor.batch` | Batch telemetry before exporting |
| `otelcol.processor.memory_limiter` | Limit memory usage |
| `discovery.kubernetes` | Discover Kubernetes targets |
| `discovery.docker` | Discover Docker containers |
| `discovery.ec2` | Discover AWS EC2 instances |
| `discovery.relabel` | Relabel discovery targets |
| `pyroscope.scrape` | Scrape profiling data |
| `pyroscope.write` | Send profiles to Pyroscope |
| `beyla.ebpf` | eBPF auto-instrumentation |

## Complete Grafana Cloud Pipeline

```alloy
// METRICS
prometheus.scrape "all" {
  targets = array.concat(
    discovery.kubernetes.nodes.targets,
    discovery.kubernetes.pods.targets,
  )
  forward_to      = [prometheus.remote_write.grafana_cloud.receiver]
  scrape_interval = "60s"
}

prometheus.remote_write "grafana_cloud" {
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

// LOGS
loki.source.kubernetes "pods" {
  targets    = discovery.kubernetes.pods.targets
  forward_to = [loki.process.add_labels.receiver]
}

loki.process "add_labels" {
  forward_to = [loki.write.grafana_cloud.receiver]
  stage.static_labels {
    values = { cluster = "prod-us-east" }
  }
}

loki.write "grafana_cloud" {
  endpoint {
    url = sys.env("LOKI_URL")
    basic_auth {
      username = sys.env("LOKI_USER")
      password = sys.env("GRAFANA_API_KEY")
    }
  }
}

// TRACES
otelcol.receiver.otlp "default" {
  grpc {}
  http {}
  output {
    traces = [otelcol.exporter.otlp.grafana_cloud.input]
  }
}

otelcol.exporter.otlp "grafana_cloud" {
  client {
    endpoint = sys.env("TEMPO_ENDPOINT")
    auth     = otelcol.auth.basic.grafana_cloud.handler
  }
}

otelcol.auth.basic "grafana_cloud" {
  username = sys.env("TEMPO_USER")
  password = sys.env("GRAFANA_API_KEY")
}

// PROFILES
pyroscope.scrape "default" {
  targets    = [{"__address__" = "localhost:6060", "service_name" = "myapp"}]
  forward_to = [pyroscope.write.grafana_cloud.receiver]
}

pyroscope.write "grafana_cloud" {
  endpoint {
    url = sys.env("PYROSCOPE_URL")
    basic_auth {
      username = sys.env("PYROSCOPE_USER")
      password = sys.env("GRAFANA_API_KEY")
    }
  }
}
```

## References

- [Components Reference](references/components.md)
- [Config Language Syntax](references/config-syntax.md)
- [Collection Patterns](references/collection-patterns.md)
