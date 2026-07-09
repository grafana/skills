# Integrations

## Alertmanager / Prometheus

```yaml
# alertmanager.yml
receivers:
  - name: grafana-oncall
    webhook_configs:
      - url: https://<your-stack>.grafana.net/integrations/v1/alertmanager/<id>/
        send_resolved: true
        max_alerts: 100        # prevent oversized payloads

route:
  receiver:        grafana-oncall
  group_by:        [alertname, cluster]
  group_wait:      30s
  group_interval:  5m
  repeat_interval: 4h
```

## Grafana Alerting (same instance)

1. OnCall / IRM → Integrations → New Integration → **Grafana Alerting**
2. Click **Quick Connect** — auto-creates a contact point
3. Link the contact point to a notification policy in Grafana Alerting

## Webhook (custom / generic)

```bash
# Send
curl -X POST https://<stack>.grafana.net/integrations/v1/formatted_webhook/<id>/ \
  -H "Content-Type: application/json" \
  -d '{
    "alert_uid": "incident-123",
    "title": "Database CPU High",
    "state": "alerting",
    "message": "db-prod-01 CPU at 95% for 10 minutes",
    "link_to_upstream_details": "https://grafana.example.com/d/abc123"
  }'

# Resolve
curl -X POST https://<stack>.grafana.net/integrations/v1/formatted_webhook/<id>/ \
  -H "Content-Type: application/json" \
  -d '{"alert_uid": "incident-123", "state": "ok"}'
```

Recognized fields: `alert_uid`, `title`, `state` (`alerting`/`ok`), `message`, `image_url`, `link_to_upstream_details`.

## Slack

1. **Install**: OnCall Settings → Chat Ops → Slack → *Install Slack Integration*
2. **Connect users**: each user → Profile → Connect to Slack
3. **Set default channel** for alert routing
4. **Add to escalation**: "Notify by Slack mentions" step

Slack message actions: Acknowledge, Resolve, Silence, Add responders, Add note.
Slash commands: `/escalate`, `/oncall`.

## RBAC roles

| Role | Access |
|------|--------|
| `oncall-admin` | Full access |
| `oncall-editor` | Create/edit integrations, schedules, escalation chains |
| `oncall-viewer` | Read-only |
| `oncall-notifications-receiver` | Receive alerts only |

## Rate limits

- 300 alerts / integration / 5 min
- 500 alerts / org / 5 min
- 300 API requests / key / 5 min
