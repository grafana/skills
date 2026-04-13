---
name: grafana-oss
license: Apache-2.0
description: >
  Grafana OSS core features — dashboards, panels, visualization types, data sources, template variables,
  alerting, annotations, provisioning, RBAC, service accounts, and configuration. Use when building
  dashboards, configuring data sources, setting up provisioning YAML, managing users and permissions,
  writing PromQL/LogQL/TraceQL in panels, or configuring Grafana server settings.
---

# Grafana OSS

> **Docs**: https://grafana.com/docs/grafana/latest/

## Dashboard Provisioning

```yaml
# provisioning/dashboards/default.yaml
apiVersion: 1
providers:
  - name: default
    folder: MyFolder
    type: file
    disableDeletion: false
    updateIntervalSeconds: 30
    options:
      path: /var/lib/grafana/dashboards
      foldersFromFilesStructure: true
```

## Data Source Provisioning

```yaml
# provisioning/datasources/datasources.yaml
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    jsonData:
      timeInterval: 15s
      httpMethod: POST

  - name: Loki
    type: loki
    access: proxy
    url: http://loki:3100

  - name: Tempo
    type: tempo
    access: proxy
    url: http://tempo:3200
    jsonData:
      tracesToLogsV2:
        datasourceUid: loki_uid
        tags: [{ key: "service.name", value: "app" }]
      serviceMap:
        datasourceUid: prometheus_uid
      nodeGraph:
        enabled: true

  - name: Pyroscope
    type: grafana-pyroscope-datasource
    url: http://pyroscope:4040
```

## Panel Types

| Panel | Use Case |
|-------|----------|
| **Time series** | Line/bar charts over time (default for metrics) |
| **Stat** | Single value with color thresholds |
| **Gauge** | Radial gauge for current value |
| **Bar gauge** | Horizontal bars for comparisons |
| **Table** | Tabular data, sortable columns |
| **Logs** | Log stream viewer (Loki) |
| **Traces** | Trace visualization (Tempo) |
| **Heatmap** | Distribution over time |
| **Histogram** | Value distribution |
| **Pie chart** | Part-to-whole ratios |
| **Geomap** | Geographic data |
| **Canvas** | Custom SVG-based layouts |
| **Node graph** | Service/topology graphs |
| **Flame graph** | CPU/memory profiling |
| **Text** | Markdown/HTML content |
| **Alert list** | Show firing alerts |

## Template Variables

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

Use variables in queries: `rate(http_requests_total{namespace="$namespace"}[$interval])`

## Alerting Configuration (grafana.ini)

```ini
[alerting]
enabled = true

[unified_alerting]
enabled = true

[smtp]
enabled = true
host = smtp.gmail.com:587
user = alerts@example.com
password = yourpassword
from_address = alerts@example.com
```

## Server Configuration (grafana.ini)

```ini
[server]
http_port = 3000
domain = grafana.example.com
root_url = https://grafana.example.com/

[database]
type = postgres
host = postgres:5432
name = grafana
user = grafana
password = secret

[auth.generic_oauth]
enabled = true
name = Okta
client_id = your_client_id
client_secret = your_secret
auth_url = https://your-org.okta.com/oauth2/v1/authorize
token_url = https://your-org.okta.com/oauth2/v1/token
api_url = https://your-org.okta.com/oauth2/v1/userinfo
scopes = openid profile email groups

[security]
admin_user = admin
admin_password = secret
allow_embedding = true       # for embedding dashboards

[feature_toggles]
enable = publicDashboards
```

## RBAC

### Built-in Roles

| Role | Permissions |
|------|-------------|
| **Viewer** | Read dashboards, alerts |
| **Editor** | Create/edit dashboards, alerts |
| **Admin** | Manage data sources, users, plugins |
| **GrafanaAdmin** | Server-wide admin (superuser) |

### Service Account Provisioning

```yaml
# provisioning/access-control/service_accounts.yaml
apiVersion: 1
serviceAccounts:
  - name: ci-reader
    orgId: 1
    role: Viewer
    tokens:
      - name: ci-token
        expires: 2025-01-01T00:00:00Z
```

### Custom RBAC Roles (Enterprise / Cloud)

```yaml
# provisioning/access-control/roles.yaml
apiVersion: 1
roles:
  - name: DashboardEditor
    description: Can create and edit dashboards
    permissions:
      - action: dashboards:create
      - action: dashboards:write
        scope: dashboards:*
      - action: folders:read
        scope: folders:*
```

## Dashboard JSON Model

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

## Annotations

```bash
# Create annotation via API
curl -X POST https://grafana.example.com/api/annotations \
  -H 'Authorization: Bearer <token>' \
  -H 'Content-Type: application/json' \
  -d '{
    "dashboardUID": "service-overview",
    "panelId": 1,
    "time": 1706745600000,
    "timeEnd": 1706749200000,
    "tags": ["deploy", "v2.0"],
    "text": "Deployed v2.0"
  }'
```

## Plugin Provisioning

```yaml
# provisioning/plugins/plugins.yaml
apiVersion: 1
apps:
  - type: grafana-pyroscope-app
    disabled: false
    jsonData:
      backendUrl: http://pyroscope:4040
```

## Key API Endpoints

```bash
# Search dashboards
GET /api/search?query=service&type=dash-db&folderIds=1

# Get dashboard
GET /api/dashboards/uid/{uid}

# Create/update dashboard
POST /api/dashboards/db
{ "dashboard": {...}, "folderUID": "...", "overwrite": true }

# List data sources
GET /api/datasources

# Create data source
POST /api/datasources

# List users
GET /api/org/users

# Create service account token
POST /api/serviceaccounts/{id}/tokens
```
