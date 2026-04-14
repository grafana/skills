---
name: oncall-irm
license: Apache-2.0
description: >
  Grafana OnCall and Incident Response Management (IRM) — alert routing, escalation chains,
  on-call schedules, Jinja2 routing templates, Slack/mobile notifications, integrations
  (Alertmanager, Grafana Alerting, webhooks, PagerDuty), and incident lifecycle management.
  Use when setting up on-call rotations, configuring escalation policies, routing alerts to
  the right team, declaring and managing incidents, integrating with Alertmanager or Grafana
  Alerting, or configuring Slack-based alert workflows.
---

# Grafana OnCall & IRM

> **OnCall docs**: https://grafana.com/docs/oncall/latest/
> **IRM docs**: https://grafana.com/docs/grafana-cloud/alerting-and-irm/

**Note:** Grafana OnCall OSS is in maintenance mode (archived March 2026). Grafana Cloud users
should use **IRM**, which unifies OnCall + Incident management. The concepts (escalation chains,
schedules, integrations) are identical.

## Core Concepts

| Concept | Description |
|---------|-------------|
| **Integration** | Entry point for alerts (HTTP POST URL); one per alert source |
| **Route** | Jinja2 condition that maps alerts to an escalation chain (first True wins) |
| **Escalation Chain** | Ordered notification steps: wait, notify schedule, notify team, etc. |
| **Schedule** | Calendar-based on-call rotation (web, iCal import, or Terraform) |
| **Alert Group** | Aggregated related alerts (grouped by Grouping ID template) |
| **Notification Policy** | Per-user delivery channels (Slack, mobile push, SMS, phone, email) |

## Alert Processing Flow

```
Alert arrives at Integration URL
  → Routing template (Jinja2, first True wins) selects escalation chain
  → Grouping ID template consolidates related alerts
  → Escalation chain fires: wait → notify schedule → wait → notify team lead
  → Users: acknowledge / resolve / silence from Slack, mobile, or web
```

## Integrations

### Alertmanager / Prometheus Alertmanager

```yaml
# alertmanager.yml
receivers:
  - name: grafana-oncall
    webhook_configs:
      - url: https://your-oncall.grafana.net/integrations/v1/alertmanager/[id]/
        send_resolved: true
        max_alerts: 100   # prevent oversized payloads

route:
  receiver: grafana-oncall
  group_by: [alertname, cluster]
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h
```

### Grafana Alerting (same instance)

1. In OnCall → Integrations → New Integration → **Grafana Alerting**
2. Click **Quick Connect** on the integration tile — auto-creates a contact point
3. Link the contact point to a notification policy in Grafana Alerting

### Webhook (custom/generic)

```bash
# Send alert via formatted webhook
curl -X POST https://your-oncall.grafana.net/integrations/v1/formatted_webhook/[id]/ \
  -H "Content-Type: application/json" \
  -d '{
    "alert_uid": "incident-123",
    "title": "Database CPU High",
    "state": "alerting",
    "message": "db-prod-01 CPU at 95% for 10 minutes",
    "link_to_upstream_details": "https://grafana.example.com/d/abc123"
  }'

# Resolve the alert
curl -X POST https://your-oncall.grafana.net/integrations/v1/formatted_webhook/[id]/ \
  -H "Content-Type: application/json" \
  -d '{"alert_uid": "incident-123", "state": "ok"}'
```

Recognized fields: `alert_uid`, `title`, `state` (`alerting`/`ok`), `message`, `image_url`, `link_to_upstream_details`

## Routing Templates (Jinja2)

Routing templates return `True` or `False` to select the escalation chain. First matching route wins.

```jinja2
{# Route critical alerts to PagerDuty escalation #}
{{ payload.labels.severity == "critical" }}

{# Route by team label #}
{{ payload.labels.team == "platform" }}

{# Route database alerts to DBA on-call #}
{{ "database" in payload.labels.get("component", "") }}

{# Default catch-all (always True) #}
{{ true }}
```

**Grouping ID** (consolidates related alerts into one alert group):
```jinja2
{{ payload.labels.alertname }}-{{ payload.labels.instance }}
```

**Advanced template functions:**
```jinja2
{{ payload.field | b64decode }}                          # Decode base64
{{ "pattern" | regex_match(payload.message) }}           # Regex matching
{{ datetimeformat_as_timezone(payload.startsAt, "UTC") }} # Timezone display
{{ payload.values | tojson_pretty }}                     # Pretty-print JSON
```

## Escalation Chains

Configure at **OnCall → Escalation Chains → Create**:

```
Step 1: Notify users from schedule "Primary On-Call" (Important Notifications)
Step 2: Wait 5 minutes
Step 3: Notify users from schedule "Primary On-Call" (Default Notifications)
Step 4: Wait 10 minutes
Step 5: Notify whole team "Platform"
Step 6: Trigger webhook (PagerDuty, ticket system, etc.)
```

**Step types:**
- **Wait** — pause N minutes before next step
- **Notify users from schedule** — alerts whoever is currently on-call
- **Notify team** — alerts all members of a team
- **Notify users** — alerts specific named users
- **Trigger outgoing webhook** — call external system
- **Auto-resolve** — mark alert group resolved after N minutes
- **Round-robin** — rotate through a list of users

## On-Call Schedules

### Web-based (UI)

Create rotations with shifts, overrides, and gaps directly in the OnCall/IRM UI.

### iCal Import

```bash
# API: create schedule from iCal
curl -X POST https://your-oncall.grafana.net/api/v1/schedules/ \
  -H "Authorization: your-api-key" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Platform On-Call",
    "ical_url_primary": "https://calendar.example.com/platform-oncall.ics",
    "ical_url_overrides": "https://calendar.example.com/overrides.ics",
    "slack": {
      "channel_id": "C123456ABC",
      "user_group_id": "S123456ABC"
    }
  }'
```

### Terraform

```hcl
resource "grafana_oncall_schedule" "platform" {
  name = "Platform On-Call"
  type = "calendar"

  shifts = [
    grafana_oncall_on_call_shift.weekday.id,
    grafana_oncall_on_call_shift.weekend.id,
  ]
}

resource "grafana_oncall_on_call_shift" "weekday" {
  name       = "Weekday"
  type       = "rolling_users"
  start      = "2024-01-01T09:00:00"
  duration   = 3600 * 8    # 8 hours
  frequency  = "weekly"
  users_per_slot = 1
  rolling_users  = [["user-id-1"], ["user-id-2"], ["user-id-3"]]
}
```

## Slack Integration

1. **Install**: OnCall Settings → Chat Ops → Slack → Install Slack Integration
2. **Connect users**: Each user: Profile → Connect to Slack
3. **Set default channel**: for alert routing
4. **Add to escalation**: "Notify by Slack mentions" step in escalation chain

Slack actions on alert messages: **Acknowledge**, **Resolve**, **Silence**, **Add responders**, **Add note**

Slash commands: `/escalate`, `/oncall`

## API Reference

Base URL: `https://your-oncall.grafana.net/api/v1/`

```bash
TOKEN=your-api-key

# List integrations
curl "$BASE/integrations/" -H "Authorization: $TOKEN"

# Create escalation chain
curl -X POST "$BASE/escalation_chains/" \
  -H "Authorization: $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name": "Platform Critical", "team_id": "team-id"}'

# List schedules
curl "$BASE/schedules/" -H "Authorization: $TOKEN"

# List alert groups
curl "$BASE/alert_groups/?page=1&perpage=25" -H "Authorization: $TOKEN"

# Who is on-call right now
curl "$BASE/schedules/{schedule_id}/next_shifts/" -H "Authorization: $TOKEN"
```

**Rate limits:** 300 alerts/integration per 5 min, 500 alerts/org per 5 min, 300 API requests/key per 5 min

## Incident Management (IRM)

When an alert group becomes an incident:

1. **Declare incident**: From alert group → "Declare Incident" or via Slack `/incident declare`
2. **Set severity**: P1–P4
3. **Add responders**: Page additional team members
4. **Update status**: Investigating → Identified → Monitoring → Resolved
5. **Timeline**: Auto-tracks all actions; add manual notes
6. **Postmortem**: Auto-generated draft from timeline on resolution

## RBAC Roles

| Role | Access |
|------|--------|
| `oncall-admin` | Full access to all OnCall resources |
| `oncall-editor` | Create/edit integrations, schedules, escalation chains |
| `oncall-viewer` | Read-only |
| `oncall-notifications-receiver` | Receive alerts; cannot modify configuration |

## Rate Limits & Best Practices

- Keep escalation chains short (≤4 levels) with a definitive final step
- Set `send_resolved: true` in Alertmanager for auto-resolution
- Use `max_alerts: 100` in Alertmanager webhook config
- Test routes with the template editor before going live
- Combine Slack + mobile push for notification reliability
- Assign integrations/schedules to teams for access control
