---
name: alloy
license: Apache-2.0
description: Build a unified telemetry pipeline with Grafana Alloy — one OpenTelemetry-compatible binary that collects metrics, logs, traces, and profiles and ships to Grafana Cloud / Prometheus / Loki / Tempo / Pyroscope. Covers the Alloy config language (blocks, `sys.env`, component refs), `prometheus.scrape` → `remote_write`, `loki.source.file` + `loki.process` → `loki.write`, `otelcol.receiver.otlp` → `otelcol.exporter.otlp`, `pyroscope.scrape`, K8s / Docker / EC2 discovery, relabeling, modules (`import.file/git/http`), clustering, Fleet Management `remotecfg`, the Alloy UI at `:12345`, and `alloy fmt` / `alloy validate`. Use when writing a `config.alloy`, replacing Grafana Agent / OTel Collector, scraping K8s pods, parsing logs, ingesting OTLP, or debugging "Alloy isn't sending anything" — even when the user says "set up the agent", "write me a scrape config", "drop these logs before sending", or "OTel collector config" without naming Alloy.
---

# Grafana Alloy

> **Docs**: https://grafana.com/docs/alloy/latest/

OpenTelemetry-compatible collector — one binary for metrics + logs + traces + profiles.

## Prerequisites

- `alloy` CLI installed (`brew install grafana/grafana/alloy`, `apt install alloy`, or `grafana/alloy` Docker image)
- An endpoint to ship to (Grafana Cloud, Prometheus, Loki, Tempo, Pyroscope)
- API key + username for that endpoint, exported as `GRAFANA_API_KEY` etc.

## Common Workflows

### 1. Write + validate a config locally

```alloy
// config.alloy — metrics → Grafana Cloud
prometheus.scrape "app" {
  targets = [{"__address__" = "localhost:9090"}]
  forward_to = [prometheus.remote_write.cloud.receiver]
  scrape_interval = "30s"
}

prometheus.remote_write "cloud" {
  endpoint {
    url = sys.env("PROMETHEUS_URL")
    basic_auth {
      username = sys.env("PROM_USER")
      password = sys.env("GRAFANA_API_KEY")
    }
  }
}
```

```bash
# 1. Format + syntax-check (catches typos before run)
alloy fmt config.alloy
alloy validate config.alloy

# 2. Run it
alloy run config.alloy
# or as a service: systemctl restart alloy

# 3. Verify all components are healthy via the UI on port 12345
curl -s http://localhost:12345/api/v0/web/components \
  | jq '.[] | select(.health.state != "healthy") | {id, state:.health.state, msg:.health.message}'
# Expect: empty (nothing unhealthy). Otherwise the row shows the failing component + reason.

# 4. Verify samples are flowing
curl -s http://localhost:12345/metrics \
  | grep -E '^prometheus_remote_storage_(samples_total|enqueue_retries_total)' | head
# samples_total should be > 0 and rising; retries should be 0.
```

### 2. Add log shipping (file → Loki)

```alloy
loki.source.file "app_logs" {
  targets    = [{ __path__ = "/var/log/app/*.log", job = "app" }]
  forward_to = [loki.write.cloud.receiver]
}

loki.write "cloud" {
  endpoint {
    url = sys.env("LOKI_URL")
    basic_auth {
      username = sys.env("LOKI_USER")
      password = sys.env("GRAFANA_API_KEY")
    }
  }
}
```

```bash
# Verify in Grafana → Explore → Loki:
#   {job="app"}
# Expect lines streaming. If empty:
#   - check /var/log/app/*.log actually exists + readable by the alloy user
#   - http://localhost:12345 → loki.source.file.app_logs → "Targets" tab
```

### 3. Receive OTLP traces and ship to Tempo

```alloy
otelcol.receiver.otlp "default" {
  grpc { endpoint = "0.0.0.0:4317" }
  http { endpoint = "0.0.0.0:4318" }
  output { traces = [otelcol.exporter.otlp.tempo.input] }
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

```bash
# Verify in Grafana → Explore → Tempo → service.name = your-service
# At the Alloy level, watch the receiver:
curl -s http://localhost:12345/metrics | grep otelcol_receiver_accepted_spans
```

Full pattern set (Kubernetes discovery + relabel, complete Cloud pipeline for all 4 signals): [`references/collection-patterns.md`](references/collection-patterns.md).

## Reference

- [`references/config-syntax.md`](references/config-syntax.md) — block/attribute/expression grammar, `import.*`, `remotecfg`, clustering
- [`references/components.md`](references/components.md) — full component catalog with purpose + typical args
- [`references/collection-patterns.md`](references/collection-patterns.md) — end-to-end pipelines (K8s pods, OTLP, profiles, logs)

## Troubleshooting

- `alloy validate` → "component not found" → version too old; `alloy --version` and upgrade
- UI shows component `unhealthy` → click into it on http://localhost:12345 for the live error
- `prometheus_remote_storage_samples_dropped_total` rising → check `enqueue_retries_total` and the remote_write endpoint URL + creds
- No spans landing in Tempo → check `otelcol_receiver_refused_spans` and the exporter's `otelcol_exporter_sent_spans` / `otelcol_exporter_send_failed_spans`

## Resources

- [Alloy docs](https://grafana.com/docs/alloy/latest/)
- [Component reference](https://grafana.com/docs/alloy/latest/reference/components/)
- [Migrate from Grafana Agent](https://grafana.com/docs/alloy/latest/set-up/migrate/from-agent/)
