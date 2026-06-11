---
name: grafana-oss
license: Apache-2.0
description: Configure Grafana OSS — provisions dashboards from YAML, sets up data sources (Prometheus / Loki / Tempo / Pyroscope), writes dashboard JSON with template variables, builds panel queries, assigns built-in roles (Viewer / Editor / Admin / GrafanaAdmin), mints service-account tokens, edits grafana.ini server config, creates annotations, installs plugins via provisioning, and validates each step with a health-check curl. Use when building dashboards, configuring data sources, setting up provisioning YAML, picking a panel type, writing template variables, managing users and roles, configuring SMTP/OAuth in grafana.ini, creating annotations via API, troubleshooting why a provisioned dashboard isn't showing up, or running Grafana OSS locally — even when the user says "set up a Prometheus data source", "provision dashboards from git", "make a service account", or "configure SSO in OSS" without saying "Grafana OSS".
---

# Grafana OSS

> **Docs**: https://grafana.com/docs/grafana/latest.md

## Common Workflows

### Provisioning dashboards from disk

1. Drop dashboard JSON file(s) under `/var/lib/grafana/dashboards/`
2. Add a provider in `provisioning/dashboards/default.yaml` (see [§ Dashboard provisioning](#dashboard-provisioning) below)
3. Restart Grafana so the provider config is loaded
4. **Verify the dashboard landed**:
   ```bash
   curl https://grafana.example.com/api/dashboards/uid/<uid> \
     -H "Authorization: Bearer <token>" | jq '.dashboard.title'
   ```
   Returns the title → success. 404 → provisioning didn't pick it up; check Grafana server logs (`journalctl -u grafana-server | grep -i provisioning`) for parse errors.

### Provisioning data sources

1. Write `provisioning/datasources/datasources.yaml` (see [§ Data source provisioning](#data-source-provisioning) below)
2. Restart Grafana
3. **Health-check the data source via API**:
   ```bash
   curl https://grafana.example.com/api/datasources/uid/<uid>/health \
     -H "Authorization: Bearer <token>"
   # { "status": "OK", "message": "..." } → working
   # { "status": "ERROR", ... } → URL unreachable or auth misconfigured
   ```

### Creating a service account + token

1. Provision via YAML or `POST /api/serviceaccounts` (full API in [references/api.md § Users + service accounts](references/api.md#users--service-accounts))
2. Mint a token via `POST /api/serviceaccounts/{id}/tokens`
3. **Verify the token works**:
   ```bash
   curl https://grafana.example.com/api/org \
     -H "Authorization: Bearer <new-token>"
   # 200 + org JSON → token + role assignment work
   # 401 → token wrong; 403 → role wrong
   ```

## Dashboard provisioning

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

For the dashboard JSON shape itself (panels, queries, template variables), see [references/dashboard-json.md](references/dashboard-json.md).

## Data source provisioning

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

## RBAC (built-in roles)

| Role | Permissions |
|------|-------------|
| **Viewer** | Read dashboards, alerts |
| **Editor** | Create/edit dashboards, alerts |
| **Admin** | Manage data sources, users, plugins |
| **GrafanaAdmin** | Server-wide admin (superuser) |

Service-account provisioning:

```yaml
# provisioning/access-control/service_accounts.yaml
apiVersion: 1
serviceAccounts:
  - name: ci-reader
    orgId: 1
    role: Viewer
    tokens:
      - name: ci-token
        # expires: optional ISO 8601 timestamp; omit for no-expiry tokens
```

(Custom RBAC roles with fine-grained permissions are Enterprise / Cloud only — see the `grafana-cloud/admin` skill if you need those.)

## Plugin provisioning

```yaml
# provisioning/plugins/plugins.yaml
apiVersion: 1
apps:
  - type: grafana-pyroscope-app
    disabled: false
    jsonData:
      backendUrl: http://pyroscope:4040
```

After restart, verify via `GET /api/plugins/<plugin-id>/health`.

## References

- [`references/dashboard-json.md`](references/dashboard-json.md) — full dashboard JSON model + template variables + common problems (uid uniqueness, gridPos arithmetic, datasource uid matching)
- [`references/panel-types.md`](references/panel-types.md) — panel-type table + decision guide for picking the right one
- [`references/api.md`](references/api.md) — full Grafana OSS API reference (dashboards, data sources, users, service accounts, annotations) with verification curls and common failure modes
- [`references/config.md`](references/config.md) — `grafana.ini` server / database / SMTP / auth / security / feature-toggle config + restart-required issues
