---
name: dashboarding
license: Apache-2.0
description:
  Create, modify, and organise Grafana dashboards including panels, variables, transformations,
  and alerting. Use when the user asks to create a Grafana dashboard, add a panel, configure a
  time series or stat panel, add template variables, set up dashboard linking, use transformations,
  configure thresholds, build a dashboard for a service, or export dashboard JSON. Triggers on
  phrases like "create dashboard", "add panel", "time series panel", "Grafana dashboard JSON",
  "template variables", "dashboard variable", "panel transformation", "threshold", "stat panel",
  "table panel", "Grafana annotations", or "dashboard folder".
---

# Grafana Dashboard Authoring

Dashboards are JSON documents stored in Grafana. Every dashboard has panels, variables, time
range, and refresh settings. Understanding the JSON schema lets you programmatically create and
modify dashboards via the API or Grafana Assistant tools.

---

## Dashboard JSON structure

```json
{
  "title": "My Dashboard",
  "uid": "my-dashboard-v1",
  "tags": ["service", "production"],
  "time": { "from": "now-1h", "to": "now" },
  "refresh": "30s",
  "timezone": "browser",
  "schemaVersion": 41,
  "templating": { "list": [] },
  "annotations": { "list": [] },
  "panels": []
}
```

**Key fields:**
- `uid` - stable identifier used in URLs and API calls; keep it short and meaningful
- `schemaVersion` - use `41` for Grafana 11+
- `time.from` / `to` - supports relative (`now-1h`, `now-7d`) and absolute ISO timestamps
- `refresh` - auto-refresh interval (`"30s"`, `"1m"`, `"5m"`, `""` for off)

---

## Panel types and when to use them

| Panel | Use case |
|---|---|
| **Time series** | Any metric over time; the default choice for counters, rates, gauges |
| **Stat** | Single current value with optional sparkline (e.g. uptime, current RPS) |
| **Gauge** | Percent or value against a min/max (e.g. disk usage %) |
| **Bar gauge** | Compare multiple values side by side (e.g. top 10 services by RPS) |
| **Table** | Multi-column data (e.g. alert list with labels) |
| **Heatmap** | Distribution over time (e.g. request duration histogram) |
| **Logs** | Loki log streams |
| **Traces** | Tempo trace search |
| **Text** | Markdown documentation panels |
| **Candlestick** | OHLC/financial data (or min/max/avg patterns) |
| **Node graph** | Service dependency graphs |

---

## Panel JSON structure

```json
{
  "id": 1,
  "type": "timeseries",
  "title": "Request Rate",
  "gridPos": { "x": 0, "y": 0, "w": 12, "h": 8 },
  "datasource": { "type": "prometheus", "uid": "${datasource}" },
  "targets": [
    {
      "expr": "sum(rate(http_requests_total{job=\"$job\"}[5m])) by (status_code)",
      "legendFormat": "{{status_code}}",
      "refId": "A"
    }
  ],
  "fieldConfig": {
    "defaults": {
      "unit": "reqps",
      "thresholds": {
        "mode": "absolute",
        "steps": [
          { "color": "green", "value": null },
          { "color": "yellow", "value": 1000 },
          { "color": "red", "value": 5000 }
        ]
      }
    },
    "overrides": []
  },
  "options": {
    "legend": { "calcs": ["mean", "max", "last"], "displayMode": "table", "placement": "bottom" },
    "tooltip": { "mode": "multi", "sort": "desc" }
  }
}
```

**`gridPos`:** The dashboard uses a 24-column grid. Common widths: full-width=24, half=12, third=8, quarter=6. Height in grid units (1 unit ≈ 30px).

---

## Useful unit identifiers

```
# Rates
"reqps"      -- requests per second
"ops"        -- operations per second
"Bps"        -- bytes per second
"percentunit" -- 0.0-1.0 as percentage

# Storage
"bytes"      -- bytes (auto-scales to KB/MB/GB)
"decbytes"   -- decimal bytes (1 KB = 1000 B)

# Time
"ms"         -- milliseconds
"s"          -- seconds
"dtdurationms" -- duration in ms (shows as "1h 2m 3s")

# Counts
"short"      -- compact number (1.2k, 3.4M)
"none"       -- raw number
```

Full list: **Panel > Field > Unit** dropdown in Grafana UI, or the [units reference](https://grafana.com/docs/grafana/latest/panels-visualizations/configure-standard-options/#unit).

---

## Template variables

Variables make dashboards reusable across environments and services.

**Query variable (populates from metric labels):**

```json
{
  "name": "job",
  "type": "query",
  "datasource": { "type": "prometheus", "uid": "prometheus" },
  "query": { "query": "label_values(up, job)", "refId": "A" },
  "refresh": 2,
  "includeAll": true,
  "multi": true,
  "label": "Service"
}
```

**Constant variable:**

```json
{
  "name": "cluster",
  "type": "constant",
  "query": "production",
  "label": "Cluster"
}
```

**Datasource variable (switch data sources without editing queries):**

```json
{
  "name": "datasource",
  "type": "datasource",
  "pluginId": "prometheus",
  "includeAll": false,
  "label": "Prometheus"
}
```

**Use variables in queries:**

```promql
# Reference a variable in a PromQL query
rate(http_requests_total{job=~"$job"}[5m])

# Multi-value variable uses regex OR automatically
# When $job = ["api", "worker"], it becomes job=~"api|worker"
```

**Chain variables** (second variable filters based on first):

```json
{
  "name": "pod",
  "query": "label_values(kube_pod_info{namespace=\"$namespace\"}, pod)"
}
```

---

## Transformations

Transformations run client-side after data is fetched, reshaping results without changing queries.

**Common transformations:**

```json
"transformations": [
  {
    "id": "merge",
    "options": {}
  },
  {
    "id": "organize",
    "options": {
      "renameByName": { "Value #A": "Request Rate", "Value #B": "Error Rate" },
      "excludeByName": { "Time": true }
    }
  },
  {
    "id": "calculateField",
    "options": {
      "alias": "Error %",
      "mode": "reduceRow",
      "reduce": { "reducer": "last" },
      "binary": {
        "left": "errors",
        "right": "total",
        "operator": "/"
      }
    }
  },
  {
    "id": "filterByValue",
    "options": {
      "filters": [{ "fieldName": "Error %", "config": { "id": "greater", "options": { "value": 0.01 } } }],
      "type": "include",
      "match": "any"
    }
  }
]
```

**Key transformation IDs:** `merge`, `organize`, `rename`, `calculateField`, `filterByValue`,
`groupBy`, `sortBy`, `limit`, `labelsToFields`, `seriesToRows`, `partitionByValues`.

---

## Dashboard linking

**Panel link (click a panel to go somewhere):**

```json
"links": [
  {
    "title": "Go to details",
    "url": "/d/details-dashboard?var-service=${__field.labels.service}",
    "targetBlank": false
  }
]
```

**Dashboard link (top-right corner links):**

```json
"links": [
  {
    "title": "Runbook",
    "url": "https://wiki.example.com/runbook/${job}",
    "icon": "external link",
    "targetBlank": true,
    "type": "link"
  }
]
```

**Built-in variables for links:**
- `${__value.raw}` - current data point value
- `${__field.labels.job}` - label value from current series
- `${__url.params}` - current URL query parameters (pass-through)
- `${__from}` / `${__to}` - current time range as Unix ms

---

## Annotations

Show events overlaid on time series panels (deployments, incidents, etc.).

**Query annotation from Loki:**

```json
{
  "datasource": { "type": "loki", "uid": "loki" },
  "expr": "{job=\"deployments\"} |= \"deployed\"",
  "name": "Deployments",
  "iconColor": "blue",
  "titleFormat": "{{service}} deployed",
  "textFormat": "{{version}} by {{author}}"
}
```

**Query annotation from Prometheus:**

```json
{
  "datasource": { "type": "prometheus", "uid": "prometheus" },
  "expr": "changes(kube_deployment_status_observed_generation{namespace=\"production\"}[5m]) > 0",
  "step": "60s",
  "name": "Deployments",
  "iconColor": "blue",
  "titleFormat": "Deploy: {{deployment}}"
}
```

---

## Dashboard via API

```bash
# Create or update a dashboard
curl -s -X POST \
  -H "Authorization: Bearer <API_KEY>" \
  -H "Content-Type: application/json" \
  "https://myorg.grafana.net/api/dashboards/db" \
  -d '{
    "dashboard": { <dashboard JSON> },
    "folderUid": "my-folder",
    "overwrite": true,
    "message": "Updated via API"
  }'

# Get a dashboard by UID
curl -s -H "Authorization: Bearer <API_KEY>" \
  "https://myorg.grafana.net/api/dashboards/uid/my-dashboard-v1" | jq '.dashboard'

# Search dashboards
curl -s -H "Authorization: Bearer <API_KEY>" \
  "https://myorg.grafana.net/api/search?query=kubernetes&type=dash-db" | \
  jq '.[] | {uid, title, folderTitle}'

# Create a folder
curl -s -X POST \
  -H "Authorization: Bearer <API_KEY>" \
  -H "Content-Type: application/json" \
  "https://myorg.grafana.net/api/folders" \
  -d '{"uid": "platform-team", "title": "Platform Team"}'
```

---

## Grafana scenes (app plugins)

For dashboards embedded in app plugins, use `@grafana/scenes` instead of raw JSON.
See the `grafana-o11y:grafana-scenes` skill for the React-based scenes API.

---

## References

- [Grafana dashboard documentation](https://grafana.com/docs/grafana/latest/dashboards/)
- [Grafana panel types reference](https://grafana.com/docs/grafana/latest/panels-visualizations/)
- [Grafana HTTP API — dashboards](https://grafana.com/docs/grafana/latest/developers/http_api/dashboard/)
- [Dashboard variables](https://grafana.com/docs/grafana/latest/dashboards/variables/)
- [Transformations reference](https://grafana.com/docs/grafana/latest/panels-visualizations/query-transform-data/transform-data/)
