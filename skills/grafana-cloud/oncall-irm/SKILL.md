---
name: oncall-irm
license: Apache-2.0
description: Route alerts, run on-call rotations, and drive incidents in Grafana IRM / OnCall — integrations (Alertmanager / Grafana Alerting / generic webhook / PagerDuty), Jinja2 routing + grouping templates, escalation chains (wait → notify schedule → notify team → webhook → auto-resolve), schedules (web + iCal + Terraform `grafana_oncall_schedule`), Slack chatops with Acknowledge/Resolve/Silence, and the P1-P4 incident lifecycle. Use when wiring Alertmanager to OnCall, deciding which team gets paged, building rotations from a Google Calendar / iCal, hooking up Slack notifications, or declaring an incident from an alert — even when the user says "page the platform team on critical alerts", "send Prometheus alerts to Slack", "set up our on-call rota", "escalation policy", or "auto-resolve when the alert clears" without naming OnCall / IRM. Heads up — OnCall OSS is in maintenance mode (archived March 2026); Grafana Cloud users should use IRM.
---

# Grafana OnCall & IRM

> **OnCall docs**: https://grafana.com/docs/oncall/latest/
> **IRM docs**: https://grafana.com/docs/grafana-cloud/alerting-and-irm/

> Grafana OnCall OSS is in maintenance mode (archived March 2026). Cloud users → **IRM**. Concepts (chains, schedules, integrations) are identical.

## Prerequisites

- Grafana Cloud stack with IRM/OnCall enabled
- API token (`Authorization: <token>`)
- Slack workspace + admin to install the OnCall app (for ChatOps)

## Core concepts

| Concept | Description |
|---------|-------------|
| **Integration** | Webhook URL accepting alerts; one per source |
| **Route** | Jinja2 condition that maps to an escalation chain (first True wins) |
| **Escalation Chain** | Wait / notify schedule / notify team / webhook / auto-resolve steps |
| **Schedule** | Calendar-based rotation (web / iCal / Terraform) |
| **Alert Group** | Related alerts collapsed by a Grouping ID template |
| **Notification Policy** | Per-user channels — Slack, mobile push, SMS, phone, email |

Flow: alert → integration → routing template → escalation chain → notifications → ack / resolve.

## Common Workflows

### 1. Wire Alertmanager → IRM and verify routing

```yaml
# 1. In IRM: New integration → Alertmanager. Copy the webhook URL.
# 2. alertmanager.yml (see references/integrations.md for full block):
receivers:
  - name: grafana-oncall
    webhook_configs:
      - url: https://<stack>.grafana.net/integrations/v1/alertmanager/<id>/
        send_resolved: true
        max_alerts: 100
```

```bash
# 3. Test the routing template BEFORE going live (UI: Integration → Route → "Preview")
#    Paste a sample payload (use a real Alertmanager test webhook). Expect:
#      Routing result: True
#      Escalation chain selected: <expected chain>
#    If False — your Jinja expression is wrong; fix and re-preview.

# 4. End-to-end test — fire amtool (or any test webhook) at the URL
amtool alert add foo severity=critical team=platform --alertmanager.url http://localhost:9093

# 5. Verify in IRM → Alert Groups (should appear within ~5s) — confirm:
#    - Correct route fired
#    - Correct schedule/user notified
#    - Slack message appeared in the configured channel
```

Routing template syntax + Jinja helpers: [`references/templates-schedules.md`](references/templates-schedules.md).
Other integrations (Grafana Alerting, generic webhook, Slack): [`references/integrations.md`](references/integrations.md).

### 2. Build an escalation chain + verify

```
1. Notify "Primary On-Call" (Important Notifications)
2. Wait 5 min
3. Notify "Primary On-Call" (Default Notifications)
4. Wait 10 min
5. Notify team "Platform"
6. Trigger outgoing webhook (PagerDuty / ticket)
```

```bash
# Verify: create a test alert (UI → Integration → "Send demo alert"),
# then watch the alert-group timeline tick through steps 1 → 6.
# Use IRM → Escalation Chains → "Test" if available, otherwise the demo alert is the canonical check.
```

### 3. Create a schedule from iCal + verify "who is on-call right now"

```bash
# 1. Create the schedule
curl -X POST https://<stack>.grafana.net/api/v1/schedules/ \
  -H "Authorization: <token>" -H "Content-Type: application/json" \
  -d '{"name":"Platform On-Call",
       "ical_url_primary":"https://calendar.example.com/platform.ics",
       "slack":{"channel_id":"C123456ABC","user_group_id":"S123456ABC"}}'

# 2. Verify the schedule was created
curl -s https://<stack>.grafana.net/api/v1/schedules/ \
  -H "Authorization: <token>" | jq '.results[] | select(.name=="Platform On-Call")'

# 3. Verify who is on-call right now
curl -s https://<stack>.grafana.net/api/v1/schedules/<schedule_id>/next_shifts/ \
  -H "Authorization: <token>" | jq '.results[0]'
# Expect a shift starting now (or recently) with the right user_id.
```

Terraform variant + shift block: [`references/templates-schedules.md`](references/templates-schedules.md).

## Best practices

- Keep chains ≤4 levels with a definitive final step (webhook to PagerDuty or auto-resolve)
- Always set `send_resolved: true` in Alertmanager so OnCall auto-resolves
- Use `max_alerts: 100` in Alertmanager webhook config
- Combine Slack + mobile push for delivery reliability
- Assign integrations/schedules to teams for RBAC

## Resources

- [OnCall API](https://grafana.com/docs/oncall/latest/oncall-api-reference/)
- [IRM docs](https://grafana.com/docs/grafana-cloud/alerting-and-irm/)
- [Routing template helpers](https://grafana.com/docs/oncall/latest/configure/jinja2-template-functions/)
