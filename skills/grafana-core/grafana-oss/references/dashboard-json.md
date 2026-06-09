# Dashboard JSON model + template variables

## Minimal dashboard JSON

```json
{
  "title": "Service Overview",
  "uid": "service-overview",
  "time": { "from": "now-1h", "to": "now" },
  "refresh": "30s",
  "panels": [
    {
      "type": "timeseries",
      "title": "Request Rate",
      "gridPos": { "x": 0, "y": 0, "w": 12, "h": 8 },
      "targets": [
        {
          "datasource": { "type": "prometheus" },
          "expr": "rate(http_requests_total{job=\"$job\"}[5m])",
          "legendFormat": "{{method}} {{status}}"
        }
      ],
      "fieldConfig": {
        "defaults": {
          "unit": "reqps",
          "thresholds": {
            "mode": "absolute",
            "steps": [
              { "color": "green", "value": null },
              { "color": "red", "value": 1000 }
            ]
          }
        }
      }
    }
  ]
}
```

## Template variables

```json
{
  "templating": {
    "list": [
      {
        "name": "namespace",
        "type": "query",
        "datasource": { "type": "prometheus", "uid": "prom" },
        "definition": "label_values(kube_pod_info, namespace)",
        "includeAll": true,
        "multi": true
      },
      {
        "name": "env",
        "type": "custom",
        "query": "production,staging,dev",
        "current": { "value": "production" }
      },
      {
        "name": "interval",
        "type": "interval",
        "query": "1m,5m,15m,1h",
        "auto": true
      }
    ]
  }
}
```

Reference variables in queries with `$variable`:
```promql
rate(http_requests_total{namespace="$namespace"}[$interval])
```

## Common problems

- **`uid` must be unique across the org** — if you POST a dashboard with an existing UID and `overwrite: false`, Grafana returns 412 Precondition Failed
- **`gridPos`** uses a 24-column grid; `w + x` must be ≤ 24
- **`datasource.uid` in `targets`** must match an existing data source UID; misspell it and panels render as "Datasource not found"
- **Template variable `query` field** is data-source-specific syntax (PromQL `label_values(...)`, LogQL `{label="…"}`, SQL, etc.)
