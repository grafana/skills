---
name: ml-ai
license: Apache-2.0
description: Turn on AI + ML features in Grafana Cloud — Grafana Assistant (NL → PromQL/LogQL/TraceQL, dashboard build, incident investigation, MCP integration), Dynamic Alerting (Prophet forecasting + DBSCAN outlier detection), Sift (8-analysis automated root-cause), Knowledge Graph + RCA Workbench, and the LLM Plugin (OpenAI / Anthropic / Azure / Ollama / vLLM / LiteLLM). Use when you want anomaly alerts without static thresholds, natural-language querying, automated incident investigation, dashboards generated from a sentence, or a managed LLM proxy for plugins — even when the user says "alert when something looks weird", "explain this PromQL", "find the root cause", "make this a dashboard", or "wire Claude into Grafana" without naming any of these products.
---

# Grafana Cloud AI & ML

> **Docs**: https://grafana.com/docs/grafana-cloud/alerting-and-irm/machine-learning/

ML alerting + automated RCA + LLM-powered Assistant in one Grafana Cloud stack.

## Prerequisites

- Grafana Cloud stack (Pro / Advanced — most features GA, some in preview)
- API token with `plugins:write` for ML / Sift / LLM-plugin endpoints
- For Dynamic Alerting: at least 14 days (ideally 90d) of history for the metric you want to forecast

## Common Workflows

### 1. Forecasting alert with Dynamic Alerting

```bash
# 1. Create forecast job (Prophet — learns daily/weekly seasonality)
curl -X POST https://<stack>.grafana.net/api/plugins/grafana-ml-app/resources/ml/v1/forecast \
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

# 2. Verify job is producing the predicted-value metric (may take a few minutes).
#    <datasourceId> must match the datasourceId used above (find it via
#    GET /api/datasources), or run the query from Explore instead.
curl -s -H "Authorization: Bearer <token>" \
  'https://<stack>.grafana.net/api/datasources/proxy/<datasourceId>/api/v1/query?query=ml_forecast_upper{job="cpu-forecast"}' \
  | jq '.data.result | length'
# Expect > 0

# 3. Add an alert that fires when actual exceeds the upper bound
# expr:  avg(rate(node_cpu_seconds_total{mode="user"}[5m]))
#         > ml_forecast_upper{job="cpu-forecast"} * 1.1
```

### 2. Outlier alert — one service deviates from peers

```bash
# 1. Create outlier job (DBSCAN — groups peers, flags the odd one)
curl -X POST https://<stack>.grafana.net/api/plugins/grafana-ml-app/resources/ml/v1/outlier \
  -H "Authorization: Bearer <token>" -H "Content-Type: application/json" \
  -d '{
    "name": "service-error-outliers",
    "metric": "sum(rate(http_requests_total{status=~\"5..\"}[5m])) by (service)",
    "datasourceId": 1,
    "interval": 300,
    "algorithm": { "name": "dbscan", "sensitivity": 0.5, "config": { "epsilon": 0.5 } }
  }'

# 2. Verify the score metric exists (<datasourceId> must match the
#    datasourceId used above, or run the query from Explore instead)
curl -s -H "Authorization: Bearer <token>" \
  'https://<stack>.grafana.net/api/datasources/proxy/<datasourceId>/api/v1/query?query=ml_outlier_score{job="service-error-outliers"}' \
  | jq '.data.result | length'

# 3. Alert when ml_outlier_score{job="service-error-outliers"} > 0.8 for 5m
```

### 3. Run a Sift investigation

```bash
# 1. Trigger from API (or from Explore / Incident / OnCall)
curl -X POST https://<stack>.grafana.net/api/plugins/grafana-sift-app/resources/sift/v1/investigations \
  -H "Authorization: Bearer <token>" -H "Content-Type: application/json" \
  -d '{ "name":"checkout-spike","start":"2024-02-01T10:00:00Z","end":"2024-02-01T10:30:00Z",
        "filters":{"service":"checkout","namespace":"production"} }'

# 2. The response includes an investigation ID — open it in the UI:
#    https://<stack>.grafana.net/a/grafana-sift-app/investigations/<id>
# 3. Verify analyses ran — each of the 8 checks shows ✔ or ✖ with linked evidence.
```

See [`references/sift.md`](references/sift.md) for the full 8-analysis table.

### 4. Wire up the LLM Plugin

```yaml
# 1. Provision (provisioning/plugins/llm.yaml — see references/llm-and-graph.md)
apiVersion: 1
apps:
  - type: grafana-llm-app
    jsonData: { openAIUrl: https://api.openai.com, openAIModel: gpt-4o }
    secureJsonData: { openAIKey: sk-... }
```

```bash
# 2. Restart Grafana, then verify the health endpoint reports the configured provider
curl -s -H "Authorization: Bearer <token>" \
  https://<stack>.grafana.net/api/plugins/grafana-llm-app/health | jq
# Expect: {"status":"ok", ...}

# 3. Verify in a panel — open any panel, click the Assistant icon, ask "what does this query do?"
```

See [`references/llm-and-graph.md`](references/llm-and-graph.md) for Assistant capabilities, Knowledge Graph search syntax, and Adaptive Metrics recommendations.

## Resources

- [Machine Learning docs](https://grafana.com/docs/grafana-cloud/alerting-and-irm/machine-learning/)
- [Sift](https://grafana.com/docs/grafana-cloud/alerting-and-irm/machine-learning/sift/)
- [Grafana Assistant](https://grafana.com/docs/grafana-cloud/visualizations/grafana-assistant/)
- [LLM Plugin](https://grafana.com/grafana/plugins/grafana-llm-app/)
