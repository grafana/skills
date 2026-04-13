---
name: ml-ai
license: Apache-2.0
description: >
  Grafana Cloud AI and ML features — Grafana Assistant (natural language queries, dashboard generation),
  Dynamic Alerting (ML-based anomaly detection), Sift (automated incident root cause analysis),
  Adaptive Metrics (cardinality reduction), and the LLM plugin for custom AI workflows.
  Use when setting up AI-powered alerting, configuring anomaly detection, using Grafana Assistant,
  setting up Sift for incident analysis, or integrating LLMs with Grafana.
---

# Grafana Cloud AI & ML

> **Docs**: https://grafana.com/docs/grafana-cloud/alerting-and-irm/machine-learning/

## Grafana Assistant

Natural language interface for querying data and building dashboards.

**Capabilities:**
- Convert natural language to PromQL/LogQL/TraceQL queries
- Explain existing queries in plain English
- Generate dashboard panels from descriptions
- Suggest visualizations based on your data
- Answer questions about your metrics and logs

**Enable:** Grafana Cloud → Settings → AI Features → Enable Grafana Assistant

**In panel editor:** Click the "Assistant" or magic wand icon to get query suggestions.

## Machine Learning: Outlier Detection

Detect outliers in metric time series using ML models.

```bash
# Create outlier job via API
curl -X POST https://yourstack.grafana.net/api/plugins/grafana-ml-app/resources/ml/v1/outlier \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "http-request-rate-outliers",
    "metric": "sum(rate(http_requests_total[5m])) by (service)",
    "datasourceId": 1,
    "interval": 300,
    "algorithm": {
      "name": "dbscan",
      "sensitivity": 0.5,
      "config": { "epsilon": 0.5 }
    }
  }'
```

**PromQL for outlier results:**
```promql
# Outlier score (>1 = outlier)
ml_outlier_score{job="my-outlier-job", service="checkout"}
```

## Machine Learning: Forecasting

Predict future metric values using time-series forecasting.

```bash
# Create forecast job
curl -X POST https://yourstack.grafana.net/api/plugins/grafana-ml-app/resources/ml/v1/forecast \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "cpu-forecast",
    "metric": "avg(node_cpu_usage)",
    "datasourceId": 1,
    "interval": 300,
    "trainingWindow": "4w",
    "forecastWindow": "7d",
    "algorithm": {
      "name": "prophet",
      "config": {}
    }
  }'
```

**PromQL for forecast:**
```promql
# Predicted value
ml_forecast{job="cpu-forecast"}

# Confidence interval
ml_forecast_lower{job="cpu-forecast"}
ml_forecast_upper{job="cpu-forecast"}
```

## Dynamic Alerting (ML-based)

Alert on anomalies without needing static thresholds:

```yaml
# Alert rule using ML outlier score
groups:
  - name: ml-alerts
    rules:
      - alert: AnomalousErrorRate
        expr: ml_outlier_score{job="error-rate-outliers"} > 0.9
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Anomalous error rate on {{ $labels.service }}"

      - alert: TrafficSpike
        expr: ml_forecast_upper{job="request-forecast"} * 1.2 < sum(rate(http_requests_total[5m]))
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Traffic significantly above forecast"
```

## Sift (Automated Root Cause Analysis)

Sift automatically investigates incidents by correlating metrics, logs, and traces.

**Trigger Sift from IRM incident:**
1. Create/open incident in Grafana IRM
2. Click "Run Sift" in the investigation panel
3. Sift queries correlated signals around the incident timeframe

**Sift investigations include:**
- Metric anomalies before/during incident
- Correlated log error spikes
- Deployment changes (via annotations)
- SLO burn rate acceleration

**API:**
```bash
# Trigger Sift investigation
curl -X POST https://yourstack.grafana.net/api/plugins/grafana-sift-app/resources/sift/v1/investigations \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "checkout-latency-spike",
    "start": "2024-02-01T10:00:00Z",
    "end": "2024-02-01T10:30:00Z",
    "filters": {
      "service": "checkout",
      "namespace": "production"
    }
  }'
```

## Adaptive Metrics

Reduce metric cardinality and storage costs by automatically identifying unused metrics.

```bash
# Get usage recommendations
curl https://yourstack.grafana.net/api/plugins/grafana-adaptive-metrics-app/resources/v1/recommendations \
  -H "Authorization: Bearer <token>"
```

**Aggregation rules** (drop high-cardinality labels):
```yaml
# Adaptive Metrics aggregation rule
- match_type: regexp
  match: "^http_request_duration_seconds.*"
  action: keep
  match_labels:
    - method
    - status
    - service
  # Drops: pod, container, instance (high cardinality)
```

## LLM Plugin (Custom AI Integration)

Connect Grafana to OpenAI, Azure OpenAI, or Anthropic for custom workflows.

```yaml
# provisioning/plugins/llm.yaml
apiVersion: 1
apps:
  - type: grafana-llm-app
    jsonData:
      openAIUrl: https://api.openai.com
      openAIModel: gpt-4o
    secureJsonData:
      openAIKey: sk-your-openai-key
```

Use in panel transformations or alerting templates:
```javascript
// In Grafana data transformation (via plugin)
const summary = await grafanaLLM.openai.chatCompletions({
  model: 'gpt-4o',
  messages: [
    { role: 'user', content: `Summarize this metric pattern: ${JSON.stringify(data)}` }
  ]
});
```
