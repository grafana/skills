---
name: ml-ai
license: Apache-2.0
description: >
  Grafana Cloud AI and ML features — Grafana Assistant (natural language queries, dashboard generation,
  incident investigations), Dynamic Alerting (ML forecasting and outlier detection), Sift (automated
  root cause analysis with 8 analysis types), Knowledge Graph (entity discovery and RCA Workbench),
  and the LLM Plugin (OpenAI/Anthropic/Azure integration). Use when setting up AI-powered alerting,
  using natural language to query metrics/logs, automating incident investigation, or integrating
  LLMs with Grafana panels and workflows.
---

# Grafana Cloud AI & ML

> **Docs**: https://grafana.com/docs/grafana-cloud/alerting-and-irm/machine-learning/

## Grafana Assistant

Context-aware LLM sidebar agent (GA). Integrates with your Grafana Cloud stack.

**Capabilities:**
- Convert natural language to PromQL/LogQL/TraceQL
- Explain existing queries in plain English
- Build and edit dashboards from descriptions
- Investigate incidents (correlate metrics, logs, traces)
- MCP server integration — connect external tools to Assistant
- RBAC controls per organization
- Slack integration for on-call workflows

**Assistant Investigations** (public preview): Multi-agent autonomous incident analysis mode — launches multiple specialized agents in parallel to investigate different signals.

**Enable:** Grafana Cloud → Administration → AI & LLM → Enable Grafana Assistant

**In panel editor:** Click the magic wand / "Assistant" icon to get query suggestions and explanations.

## Dynamic Alerting

ML-based alerting without static thresholds.

### Forecasting (Prophet model)

Trained on 90 days of history; learns daily and weekly seasonality patterns.

```bash
# Create forecast job
curl -X POST https://yourstack.grafana.net/api/plugins/grafana-ml-app/resources/ml/v1/forecast \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "cpu-forecast",
    "metric": "avg(rate(node_cpu_seconds_total{mode=\"user\"}[5m]))",
    "datasourceId": 1,
    "interval": 300,
    "trainingWindow": "90d",
    "forecastWindow": "7d",
    "algorithm": { "name": "prophet", "config": {} }
  }'
```

Generated metric pairs for alert rules:
```promql
# Predicted value
ml_forecast{job="cpu-forecast"}

# Confidence bounds
ml_forecast_lower{job="cpu-forecast"}
ml_forecast_upper{job="cpu-forecast"}

# Alert: actual > upper bound (anomaly above forecast)
avg(rate(node_cpu_seconds_total{mode="user"}[5m]))
  > ml_forecast_upper{job="cpu-forecast"} * 1.1
```

### Outlier Detection

Detects when one series in a group deviates from its peers.

```bash
curl -X POST https://yourstack.grafana.net/api/plugins/grafana-ml-app/resources/ml/v1/outlier \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "service-error-outliers",
    "metric": "sum(rate(http_requests_total{status=~\"5..\"}[5m])) by (service)",
    "datasourceId": 1,
    "interval": 300,
    "algorithm": {
      "name": "dbscan",
      "sensitivity": 0.5,
      "config": { "epsilon": 0.5 }
    }
  }'
```

```promql
# Score > 0: series is an outlier (use in alert rule)
ml_outlier_score{job="service-error-outliers", service="checkout"}
```

### Alert Rules using ML

```yaml
groups:
  - name: ml-alerts
    rules:
      - alert: CPUAboveForecast
        expr: |
          avg(rate(node_cpu_seconds_total{mode="user"}[5m]))
          > ml_forecast_upper{job="cpu-forecast"} * 1.1
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "CPU usage significantly above forecast"

      - alert: ServiceErrorRateAnomaly
        expr: ml_outlier_score{job="service-error-outliers"} > 0.8
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Anomalous error rate on {{ $labels.service }}"
```

## Sift (Automated Root Cause Analysis)

Free for all Grafana Cloud accounts. Automatically investigates incidents by correlating signals.

**8 Analysis Types:**

| Analysis | What it checks |
|----------|---------------|
| **Error Pattern Logs** | Clusters log errors by pattern, ranks by frequency/recency |
| **HTTP Error Series** | Finds HTTP 4xx/5xx spikes correlated with incident window |
| **Kube Crashes** | OOMKills, pod restarts, evictions in K8s |
| **Log Query** | Custom LogQL query results correlated to incident time |
| **Metric Query** | Custom PromQL anomalies around incident window |
| **Noisy Neighbors** | Detects resource contention from co-located services |
| **Recent Deployments** | Correlates recent Helm/K8s deployments with incident start |
| **Resource Contention** | CPU throttling, memory pressure, disk I/O saturation |

**Trigger Sift from:**
- Explore → "Run Sift Investigation"
- Dashboard panel → "Investigate with Sift"
- Grafana Incident → "Run Sift" button
- Command palette (`Cmd+K`) → "Start Sift investigation"
- OnCall escalation chains → automatic trigger

```bash
# Trigger via API
curl -X POST https://yourstack.grafana.net/api/plugins/grafana-sift-app/resources/sift/v1/investigations \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "checkout-latency-spike",
    "start": "2024-02-01T10:00:00Z",
    "end": "2024-02-01T10:30:00Z",
    "filters": { "service": "checkout", "namespace": "production" }
  }'
```

## Knowledge Graph

Auto-discovers services, pods, nodes, and namespaces from metric labels and trace data. Updates every minute.

**Access:** Observability → Entity graph

**Search syntax:**
```
Show Service api-server
Show all services in namespace production
Show Pod frontend-abc123
```

**RCA Workbench:** Structured troubleshooting interface built on the knowledge graph — traces relationships between entities to identify blast radius and upstream causes.

## LLM Plugin

Acts as an authenticated proxy for LLM provider API calls from Grafana panels and plugins.

**Supported providers:** OpenAI, Anthropic (Claude), Azure OpenAI, vLLM, Ollama, LiteLLM

**Powered features:** Flame graph interpretation, incident auto-summary, panel title generation, Sift log explanations, natural language panel descriptions.

**Enable:** Administration → Plugins → LLM Plugin → "Enable OpenAI/LLM access via Grafana"

```yaml
# provisioning/plugins/llm.yaml
apiVersion: 1
apps:
  - type: grafana-llm-app
    jsonData:
      # OpenAI
      openAIUrl: https://api.openai.com
      openAIModel: gpt-4o
      # Or Anthropic:
      # provider: anthropic
      # anthropicModel: claude-sonnet-4-6
      # Or Azure OpenAI:
      # openAIUrl: https://your-resource.openai.azure.com
      # azureModelMapping: '[["gpt-4o","your-deployment-name"]]'
    secureJsonData:
      openAIKey: sk-your-openai-key
```

## Adaptive Metrics

Identifies unused metrics to reduce cardinality and storage costs.

```bash
# Get aggregation recommendations
curl https://yourstack.grafana.net/api/plugins/grafana-adaptive-metrics-app/resources/v1/recommendations \
  -H "Authorization: Bearer <token>"
```

Aggregation rule (drops high-cardinality labels):
```yaml
- match: "^http_request_duration_seconds.*"
  action: keep
  match_labels: [method, status, service]
  # Drops: pod, container, instance
```
