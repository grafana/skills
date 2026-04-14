---
name: fleet-management
license: Apache-2.0
description:
  Install, configure, and manage Grafana Alloy collector fleets using Fleet Management and remote
  configuration pipelines. Use when the user asks to configure Alloy, manage collector pipelines,
  deploy remote configurations, troubleshoot collector health, work with OpAMP, set up pipeline
  matchers, or manage collector attributes. Triggers on phrases like "configure Alloy", "fleet
  management", "remote configuration", "collector pipeline", "OpAMP", "pipeline matcher",
  "collector attributes", "deploy pipeline", "collector is unhealthy", or "Alloy pipeline YAML".
---

# Grafana Fleet Management and Alloy Configuration

Fleet Management lets you author pipeline configurations once and distribute them to many Alloy
collectors remotely via OpAMP. Collectors poll for updates and apply new configurations without
a restart.

**Key concepts:**
- **Collector** - an Alloy agent instance, identified by a unique ID and set of attributes
- **Pipeline** - a named Alloy configuration (YAML) stored in Fleet Management
- **Matcher** - a label selector that maps a pipeline to matching collectors
- **Attributes** - key/value labels on a collector used for targeting (e.g. `env=production`)

---

## Step 1: Check the current state

```bash
BASE=https://fleet-management-prod-us-east-0.grafana.net
TOKEN=<STACK_ID>:<API_TOKEN>

# List all registered collectors and their health status
curl -s -X POST "$BASE/collector.v1.CollectorService/ListCollectors" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{}' | jq '.collectors[] | {id, name, remoteConfigStatus}'

# List all pipelines
curl -s -X POST "$BASE/pipeline.v1.PipelineService/ListPipelines" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{}'
```

In the Grafana Cloud UI: **Connections > Collector > Fleet Management > Collector Inventory**.

Healthy collectors show `REMOTE_CONFIG_STATUS_APPLIED`. Degraded collectors show
`REMOTE_CONFIG_STATUS_FAILED` with a `remoteConfigStatusMessage` describing the error.

---

## Step 2: Understand the pipeline YAML format

Pipelines are valid Alloy configuration files. Alloy uses a HCL-like syntax called River.

```alloy
// Basic metrics pipeline: scrape Prometheus metrics and forward to Grafana Cloud
prometheus.scrape "default" {
  targets    = discovery.relabel.filtered.output
  forward_to = [prometheus.remote_write.grafana_cloud.receiver]
  scrape_interval = "60s"
}

prometheus.remote_write "grafana_cloud" {
  endpoint {
    url = "https://prometheus-prod-01-eu-west-0.grafana.net/api/prom/push"
    basic_auth {
      username = "<METRICS_USERNAME>"
      password = env("GRAFANA_CLOUD_API_KEY")
    }
  }
}
```

**Key Alloy component categories:**

| Category | Example components |
|---|---|
| Discovery | `discovery.kubernetes`, `discovery.docker`, `discovery.relabel` |
| Metrics | `prometheus.scrape`, `prometheus.remote_write`, `prometheus.operator.*` |
| Logs | `loki.source.file`, `loki.source.kubernetes`, `loki.write` |
| Traces | `otelcol.receiver.otlp`, `otelcol.exporter.otlp` |
| Profiles | `pyroscope.scrape`, `pyroscope.write` |
| Transformation | `otelcol.processor.batch`, `otelcol.processor.filter` |

**Reference:** [Alloy component documentation](https://grafana.com/docs/alloy/latest/reference/components/)

---

## Step 3: Create a pipeline

```bash
# Create a pipeline via API (contents is plain text Alloy config, not base64)
curl -s -X POST "$BASE/pipeline.v1.PipelineService/CreatePipeline" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "k8s-metrics",
    "contents": "prometheus.scrape \"default\" {\n  targets = []\n  forward_to = []\n}",
    "matchers": [
      {"name": "env", "value": "production", "type": "EQUAL"}
    ]
  }'
```

In the UI: **Fleet Management > Remote Configuration > Create pipeline**. The wizard offers:
1. Start from a template (Kubernetes, host metrics, logs, traces, profiles)
2. Duplicate an existing pipeline
3. Write from scratch with the inline editor

---

## Step 4: Assign pipelines to collectors with matchers

Matchers use label selectors to map a pipeline to collectors. A collector receives all pipelines
whose matchers match its attributes.

```json
{
  "matchers": [
    "env=\"production\"",
    "team=\"platform\""
  ]
}
```

This assigns the pipeline to any collector with both `env=production` AND `team=platform`.

**Matcher syntax:**

| Operator | Example | Meaning |
|---|---|---|
| `=` | `env="production"` | Exact match |
| `!=` | `env!="dev"` | Not equal |
| `=~` | `region=~"us-.*"` | Regex match |
| `!~` | `region!~"eu-.*"` | Regex not match |

**Apply matchers when creating or updating a pipeline:**

```bash
# Matchers are set in CreatePipeline or UpdatePipeline
curl -s -X POST "$BASE/pipeline.v1.PipelineService/UpdatePipeline" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "id": "<PIPELINE_ID>",
    "matchers": [
      {"name": "env",  "value": "production", "type": "EQUAL"},
      {"name": "team", "value": "platform",   "type": "EQUAL"}
    ]
  }'
```

Matcher `type` values: `EQUAL`, `NOT_EQUAL`, `REGEX`, `NOT_REGEX`

A pipeline with no matchers is saved but deployed to zero collectors.

---

## Step 5: Set collector attributes

Attributes are the labels that matchers target. Set them from the UI (Collector Inventory > select
collector > Edit attributes) or via API:

```bash
curl -s -X POST "$BASE/collector.v1.CollectorService/UpdateCollector" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "id": "<COLLECTOR_ID>",
    "attributes": [
      {"name": "env",    "value": "production"},
      {"name": "team",   "value": "platform"},
      {"name": "region", "value": "us-east-1"}
    ]
  }'
```

**Alloy sets some attributes automatically on registration:**
- `platform` - OS platform (linux, darwin, windows)
- `arch` - CPU architecture (amd64, arm64)
- `alloy_version` - Alloy version string

Custom attributes must be set explicitly — either via the API or by the collector's startup config.

---

## Step 6: Install Alloy with remote configuration enabled

For Alloy to receive remote configuration from Fleet Management, it needs:
1. An API token with Fleet Management access
2. The `remotecfg` block in its local (bootstrap) configuration

```alloy
// bootstrap.alloy -- the only local config file Alloy needs
remotecfg {
  url = "https://<FLEET_MANAGEMENT_HOST>"

  basic_auth {
    username = "<STACK_ID>"
    password = env("GRAFANA_CLOUD_API_KEY")
  }

  poll_frequency = "1m"

  // Attributes for this collector instance
  attributes = {
    "env"    = env("ENVIRONMENT"),
    "team"   = "platform",
    "region" = env("AWS_REGION"),
  }
}
```

**Kubernetes deployment:**

```yaml
# values.yaml for grafana/alloy Helm chart
alloy:
  configMap:
    content: |
      remotecfg {
        url = "https://<FLEET_MANAGEMENT_HOST>"
        basic_auth {
          username = "<STACK_ID>"
          password = env("GRAFANA_CLOUD_API_KEY")
        }
        poll_frequency = "1m"
        attributes = {
          "env" = "production",
          "cluster" = env("CLUSTER_NAME"),
        }
      }
  extraEnv:
    - name: GRAFANA_CLOUD_API_KEY
      valueFrom:
        secretKeyRef:
          name: grafana-cloud-credentials
          key: api-key
```

---

## Step 7: Troubleshoot collector health

**Check remote config status:**

```bash
# List collectors with FAILED status
curl -s -X POST "$BASE/collector.v1.CollectorService/ListCollectors" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{}' | jq '.collectors[] | select(.remoteConfigStatus == "REMOTE_CONFIG_STATUS_FAILED") | {id, name, remoteConfigStatusMessage}'
```

**Common failure patterns:**

| Status message | Root cause | Fix |
|---|---|---|
| `syntax error at line N` | Invalid Alloy River syntax | Fix the pipeline YAML; validate before deploying |
| `component not found: X` | Alloy version too old for a component | Upgrade Alloy or use an older API |
| `failed to unmarshal config` | Base64 encoding error | Re-encode the config correctly |
| `authentication failed` | Wrong API token | Rotate and re-apply the token |
| `connection refused` | Collector can't reach Fleet Management | Check network/firewall rules |

**Check Alloy logs directly:**

```bash
# Kubernetes
kubectl logs -n monitoring -l app.kubernetes.io/name=alloy --tail=50 | grep -i "remote\|error"

# Systemd
journalctl -u alloy --since "1h ago" | grep -i "remote\|error"
```

**Check the Alloy UI** (port 12345 by default) at `http://<COLLECTOR_HOST>:12345`:
- **Graph** tab: shows component wiring and health per component
- **Components** tab: lists all components and their current config
- **Clustering** tab: shows clustering state if enabled

---

## Step 8: Use the Grafana Assistant for pipeline work

The Grafana Assistant understands Fleet Management and can:
- Explain what a pipeline configuration does
- Identify syntax errors and suggest fixes
- Optimize pipelines for performance or cost
- Generate Mermaid diagrams of component wiring

**Via the UI:** In the Remote Configuration page, select a pipeline and click the Assistant button.
Options: Explain, Validate/Fix, Optimize, Visualize.

**Via API (for automation):** The Assistant exposes Fleet Management tools:
- `fleetManagementRead` - list collectors and pipelines
- `fleetManagementWrite` - update pipeline configurations
- `alloyConfigValidation` - validate Alloy River syntax

---

## References

- [Alloy documentation](https://grafana.com/docs/alloy/latest/)
- [Fleet Management API docs](https://grafana.com/docs/grafana-cloud/send-data/fleet-management/)
- [Alloy component reference](https://grafana.com/docs/alloy/latest/reference/components/)
- [OpAMP specification](https://github.com/open-telemetry/opamp-spec)
