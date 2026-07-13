# Routing templates, schedules, escalation chains, API

## Jinja2 routing templates

Return `True` / `False`. First matching route wins.

```jinja2
{# Critical → PagerDuty escalation #}
{{ payload.labels.severity == "critical" }}

{# Team-based #}
{{ payload.labels.team == "platform" }}

{# Substring on a label #}
{{ "database" in payload.labels.get("component", "") }}

{# Default catch-all #}
{{ true }}
```

Grouping ID (consolidates related alerts):

```jinja2
{{ payload.labels.alertname }}-{{ payload.labels.instance }}
```

Advanced template helpers:

```jinja2
{{ payload.field | b64decode }}
{{ "pattern" | regex_match(payload.message) }}
{{ datetimeformat_as_timezone(payload.startsAt, "UTC") }}
{{ payload.values | tojson_pretty }}
```

## Escalation chain step types

- **Wait** — pause N minutes
- **Notify users from schedule** — current on-call
- **Notify team** — all team members
- **Notify users** — specific named users
- **Trigger outgoing webhook**
- **Auto-resolve** after N minutes
- **Round-robin** through a list

Example chain:

```
1. Notify "Primary On-Call" (Important Notifications)
2. Wait 5 min
3. Notify "Primary On-Call" (Default Notifications)
4. Wait 10 min
5. Notify team "Platform"
6. Trigger webhook (PagerDuty / ticketing)
```

## On-call schedule — iCal import

```bash
curl -X POST https://<stack>.grafana.net/api/v1/schedules/ \
  -H "Authorization: <api-key>" -H "Content-Type: application/json" \
  -d '{
    "name": "Platform On-Call",
    "ical_url_primary":   "https://calendar.example.com/platform-oncall.ics",
    "ical_url_overrides": "https://calendar.example.com/overrides.ics",
    "slack": { "channel_id": "C123456ABC", "user_group_id": "S123456ABC" }
  }'
```

## Terraform schedule + shift

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
  name           = "Weekday"
  type           = "rolling_users"
  start          = "2024-01-01T09:00:00"
  duration       = 3600 * 8
  frequency      = "weekly"
  users_per_slot = 1
  rolling_users  = [["user-id-1"], ["user-id-2"], ["user-id-3"]]
}
```

## API quick reference

Base URL: `https://<stack>.grafana.net/api/v1/`

```bash
TOKEN=<api-key>; BASE=https://<stack>.grafana.net/api/v1
curl "$BASE/integrations/"                    -H "Authorization: $TOKEN"
curl -X POST "$BASE/escalation_chains/"       -H "Authorization: $TOKEN" \
     -H "Content-Type: application/json" -d '{"name":"Platform Critical","team_id":"<id>"}'
curl "$BASE/schedules/"                       -H "Authorization: $TOKEN"
curl "$BASE/alert_groups/?page=1&perpage=25"  -H "Authorization: $TOKEN"
curl "$BASE/schedules/<schedule_id>/next_shifts/" -H "Authorization: $TOKEN"
```

## Incident lifecycle (IRM)

When an alert group escalates to incident:

1. **Declare** — alert group → "Declare Incident" or Slack `/incident declare`
2. **Severity** — P1-P4
3. **Add responders**
4. **Status flow** — Investigating → Identified → Monitoring → Resolved
5. **Timeline** auto-tracks all actions; add manual notes
6. **Postmortem** — auto-draft from timeline on resolution
