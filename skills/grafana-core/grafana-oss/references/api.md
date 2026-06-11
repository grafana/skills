# Grafana OSS API

Base URL: `https://your-grafana.example.com/api/`. Auth: service account token (`Authorization: Bearer <token>`).

## Contents

- [Dashboards](#dashboards)
- [Data sources](#data-sources)
- [Users + service accounts](#users--service-accounts)
- [Annotations](#annotations)

## Dashboards

```bash
# Search
GET /api/search?query=service&type=dash-db&folderIds=1

# Get by UID
GET /api/dashboards/uid/{uid}

# Create / update (overwrite: true replaces existing)
POST /api/dashboards/db
Body: { "dashboard": {...}, "folderUID": "...", "overwrite": true }

# Delete
DELETE /api/dashboards/uid/{uid}
```

After provisioning a dashboard via YAML, verify it landed:
```bash
curl https://grafana.example.com/api/dashboards/uid/<uid> \
  -H "Authorization: Bearer <token>" | jq '.dashboard.title'
# Should print the dashboard's title. 404 = not provisioned correctly.
```

## Data sources

```bash
# List
GET /api/datasources

# Get by UID
GET /api/datasources/uid/{uid}

# Create
POST /api/datasources
Body: { "name": "...", "type": "...", "url": "...", "access": "proxy" }

# Health-check (good post-provision validation)
GET /api/datasources/uid/{uid}/health
# Returns { "status": "OK" | "ERROR", "message": "..." }
```

## Users + service accounts

```bash
# List org users
GET /api/org/users

# List service accounts
GET /api/serviceaccounts/search?perpage=100&page=1

# Create service account
POST /api/serviceaccounts
Body: { "name": "ci-reader", "role": "Viewer", "isDisabled": false }

# Mint a token
POST /api/serviceaccounts/{id}/tokens
Body: { "name": "ci-token", "secondsToLive": 0 }   # 0 = no expiry

# Verify a token works
curl https://grafana.example.com/api/org \
  -H "Authorization: Bearer <new-token>"
# 200 + org JSON = token + role assignment work.
```

## Annotations

```bash
# Create
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

# Find (by tag)
GET /api/annotations?tags=deploy&from=1706745600000&to=1706832000000

# Delete
DELETE /api/annotations/{id}
```

## Common failure modes

| Symptom | Likely cause |
|---|---|
| `401 Unauthorized` | Token expired or wrong stack URL — check the Authorization header |
| `403 Forbidden` on dashboard create | Service account lacks Editor role on the target folder |
| `412 Precondition Failed` on POST `/dashboards/db` | UID exists and you didn't set `overwrite: true` |
| Data source health check `ERROR` | Network unreachable (check `url` field) or credentials wrong |
