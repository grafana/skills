# Admin API reference

Endpoints split by audience: Cloud-level (manage stacks, orgs from grafana.com) vs Stack-level (per-instance Grafana API).

## Contents

- [Cloud API — stack management](#cloud-api-stack-management)
- [Stack API — user / team / org management](#stack-api-user-team-org-management)
- [Audit logs](#audit-logs)

## Cloud API — stack management

Base URL: `https://grafana.com/api/`. Auth: grafana.com API key.

```bash
# List stacks
curl https://grafana.com/api/instances \
  -H "Authorization: Bearer <grafana-com-api-key>"

# Create stack
curl -X POST https://grafana.com/api/instances \
  -H "Authorization: Bearer <grafana-com-api-key>" \
  -H "Content-Type: application/json" \
  -d '{"name": "my-new-stack", "slug": "my-new-stack", "region": "us-east-0", "plan": "grafana-cloud-free"}'

# Verify stack is reachable (poll until 200)
curl https://my-new-stack.grafana.net/api/health

# Delete stack
curl -X DELETE https://grafana.com/api/instances/{id} \
  -H "Authorization: Bearer <grafana-com-api-key>"

# Verify deletion
curl https://grafana.com/api/instances/{id} \
  -H "Authorization: Bearer <grafana-com-api-key>"
# Should return 404
```

## Stack API — user / team / org management

Base URL: `https://yourstack.grafana.net/api/`. Auth: Grafana service account token.

```bash
# List org users
GET /api/org/users

# Invite user to org
POST /api/org/invites
Body: { "loginOrEmail": "user@example.com", "role": "Editor", "sendEmail": true }

# Update user org role
PATCH /api/org/users/{userId}
Body: { "role": "Admin" }

# List teams
GET /api/teams/search?name=platform

# Create team
POST /api/teams
Body: { "name": "Platform Team", "email": "platform@example.com" }

# Add user to team
POST /api/teams/{teamId}/members
Body: { "userId": 2 }

# Look up a user (useful after SSO config changes)
GET /api/users/lookup?loginOrEmail=alice@example.com
```

## Audit logs

```bash
# Query audit logs (Enterprise / Cloud only)
GET /api/admin/auditlogs?query=login&from=1706745600&to=1706832000&limit=50
```

`from` and `to` are Unix epoch seconds. The `query` parameter is a free-text search over event names (`login`, `dashboard.create`, `team.member.add`, etc.).

## Common failure modes

| Symptom | Likely cause |
|---|---|
| `401 Unauthorized` | Token expired or wrong stack URL — check `Authorization` header |
| `403 Forbidden` on `/api/admin/*` | Service account lacks `Admin` role on the org |
| `404` on a known stack | Wrong region in URL (`us-east-0` vs `eu-west-0`) |
| Audit logs empty for a known event | Audit logging may not be enabled on free tier — confirm Enterprise/Cloud subscription |
