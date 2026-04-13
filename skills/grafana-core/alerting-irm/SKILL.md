---
name: alerting-irm
license: Apache-2.0
description: >
  Grafana Alerting, Incident Response Management (IRM), and SLOs. Covers Grafana-managed and data source-managed
  alert rules, notification policies, contact points (Slack/PagerDuty/email/webhook), silences, muting,
  on-call scheduling, incident management workflows, and SLO configuration with burn-rate alerts.
  Use when configuring alerts, debugging notification routing, setting up on-call rotations,
  managing incidents, defining SLOs, or provisioning alerting via YAML/API.
---

# Grafana Alerting & IRM

> **Docs**: https://grafana.com/docs/grafana/latest/alerting/

## Alert Rules

### Grafana-Managed Alert Rule (YAML provisioning)

```yaml
# provisioning/alerting/rules.yaml
apiVersion: 1
groups:
  - orgId: 1
    name: MyAlertGroup
    folder: MyFolder
    interval: 1m
    rules:
      - uid: high-error-rate
        title: High Error Rate
        condition: C
        data:
          - refId: A
            datasourceUid: prometheus
            relativeTimeRange:
              from: 300   # 5 minutes
              to: 0
            model:
              expr: sum(rate(http_requests_total{status=~"5.."}[5m])) by (service)
          - refId: B
            datasourceUid: __expr__
            model:
              type: reduce
              refId: B
              expression: A
              reducer: last
          - refId: C
            datasourceUid: __expr__
            model:
              type: math
              refId: C
              expression: $B > 0.05
        noDataState: NoData
        execErrState: Alerting
        for: 5m
        labels:
          severity: critical
          team: platform
        annotations:
          summary: "High error rate on {{ $labels.service }}"
          description: "Error rate is {{ $values.B }}%"
          runbook_url: "https://runbooks.example.com/high-error-rate"
```

### Prometheus/Mimir Alert Rule (ruler)

```yaml
groups:
  - name: service-alerts
    interval: 1m
    rules:
      - alert: HighErrorRate
        expr: |
          sum(rate(http_requests_total{status=~"5.."}[5m])) by (service)
          /
          sum(rate(http_requests_total[5m])) by (service)
          > 0.05
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "High error rate: {{ $labels.service }}"

      - alert: HighLatency
        expr: histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m])) > 1
        for: 2m
        labels:
          severity: warning
        annotations:
          summary: "P95 latency > 1s on {{ $labels.service }}"

      # Recording rule
      - record: job:http_requests:rate5m
        expr: sum(rate(http_requests_total[5m])) by (job)
```

### Loki Alert Rule (LogQL)

```yaml
groups:
  - name: log-alerts
    rules:
      - alert: HighErrorLogs
        expr: |
          sum(rate({app="myapp"} |= "error" [5m])) by (app)
          /
          sum(rate({app="myapp"}[5m])) by (app)
          > 0.05
        for: 10m
        labels:
          severity: page
        annotations:
          summary: "High error log rate for {{ $labels.app }}"

      - alert: CredentialsLeak
        expr: |
          sum by (cluster, job, pod) (
            count_over_time({namespace="prod"} |~ "https?://(\\w+):(\\w+)@" [5m]) > 0
          )
        for: 5m
        labels:
          severity: critical
```

## Contact Points (YAML provisioning)

```yaml
# provisioning/alerting/contact_points.yaml
apiVersion: 1
contactPoints:
  - orgId: 1
    name: pagerduty-critical
    receivers:
      - uid: pd-receiver
        type: pagerduty
        settings:
          integrationKey: YOUR_PAGERDUTY_KEY
          severity: critical

  - orgId: 1
    name: slack-alerts
    receivers:
      - uid: slack-receiver
        type: slack
        settings:
          url: https://hooks.slack.com/services/YOUR/WEBHOOK/URL
          channel: '#alerts'
          username: Grafana
          icon_emoji: ':grafana:'
          title: '{{ template "slack.default.title" . }}'
          text: '{{ template "slack.default.text" . }}'

  - orgId: 1
    name: email-alerts
    receivers:
      - uid: email-receiver
        type: email
        settings:
          addresses: 'oncall@example.com;alerts@example.com'

  - orgId: 1
    name: webhook-alerts
    receivers:
      - uid: webhook-receiver
        type: webhook
        settings:
          url: https://your-endpoint.com/grafana-alerts
          httpMethod: POST
```

## Notification Policies (YAML provisioning)

```yaml
# provisioning/alerting/policies.yaml
apiVersion: 1
policies:
  - orgId: 1
    receiver: default-receiver
    group_by: ['alertname', 'cluster', 'service']
    group_wait: 30s
    group_interval: 5m
    repeat_interval: 12h
    routes:
      # Critical alerts → PagerDuty
      - receiver: pagerduty-critical
        matchers:
          - severity = critical
        group_wait: 10s
        group_interval: 1m
        repeat_interval: 4h

      # Platform team alerts → Slack
      - receiver: slack-alerts
        matchers:
          - team = platform
        routes:
          # Critical platform → page immediately
          - receiver: pagerduty-critical
            matchers:
              - severity = critical

      # Everything else → email
      - receiver: email-alerts
        matchers:
          - severity =~ "warning|info"
```

## Silences

Silences suppress notifications for matching alerts without stopping evaluation.

```bash
# Via API - create a silence
curl -X POST https://grafana.example.com/api/alertmanager/grafana/api/v2/silences \
  -H 'Content-Type: application/json' \
  -d '{
    "matchers": [
      {"name": "alertname", "value": "HighErrorRate", "isRegex": false},
      {"name": "env", "value": "staging", "isRegex": false}
    ],
    "startsAt": "2024-01-01T00:00:00Z",
    "endsAt": "2024-01-01T02:00:00Z",
    "comment": "Maintenance window",
    "createdBy": "admin"
  }'
```

## Alert Rule States

| State | Description |
|-------|-------------|
| **Normal** | Condition not met |
| **Pending** | Condition met, waiting for `for` duration |
| **Firing** | Condition met for full `for` duration |
| **NoData** | Query returned no data |
| **Error** | Query/evaluation error |
| **Recovering** | Was firing, condition no longer met |

## SLOs

```yaml
# SLO configuration (via Grafana UI or API)
# Grafana auto-generates recording rules, dashboards, and burn-rate alerts

# Generated recording rules example:
groups:
  - name: slo_availability
    interval: 1m
    rules:
      - record: slo:availability:ratio_rate5m
        expr: |
          sum(rate(http_requests_total{status!~"5.."}[5m])) by (service)
          / sum(rate(http_requests_total[5m])) by (service)

      - record: slo:error_budget:remaining
        expr: |
          (slo:availability:ratio_rate30d - 0.999) / (1 - 0.999)

# Burn rate alerts (auto-generated by Grafana SLO)
- alert: SLOBurnRateHigh
  expr: |
    slo:burn_rate:ratio_rate1h > 14.4      # 1h window, 5% budget in 1h
  for: 2m
  labels:
    severity: critical
  annotations:
    summary: "SLO burn rate critical for {{ $labels.service }}"
```

## IRM - On-Call and Incidents

### Key IRM Capabilities

- **On-Call Schedules**: Rotating shifts, overrides, escalation policies
- **Alert Routing**: Route from Grafana Alerting, Prometheus, Datadog, PagerDuty, etc.
- **Incident Management**: Declare incidents, add participants, track tasks/timeline
- **Escalation Chains**: Auto-escalate if no response after N minutes
- **Integrations**: Slack, Teams, Telegram, GitHub, Jira, StatusPage

### IRM Integration Sources

| Source | Setup |
|--------|-------|
| Grafana Alerting | Native - configure in contact points |
| Prometheus Alertmanager | Webhook URL from IRM |
| Datadog | Webhook integration |
| PagerDuty | Event integration |
| Jira | Issue alerts |
| Custom | Generic webhook |

## Provisioning Directory Structure

```
provisioning/alerting/
├── alert_rules.yaml        # Alert and recording rules
├── contact_points.yaml     # Notification destinations
├── notification_policies.yaml  # Routing tree
├── templates.yaml          # Message templates
└── mute_timings.yaml       # Recurring mute windows
```

## API Provisioning (Keeps UI Editable)

```bash
# Get current notification policy
curl https://grafana.example.com/api/v1/provisioning/policies \
  -H 'Authorization: Bearer <token>'

# Update (add X-Disable-Provenance to keep editable in UI)
curl -X PUT https://grafana.example.com/api/v1/provisioning/policies \
  -H 'Authorization: Bearer <token>' \
  -H 'X-Disable-Provenance: true' \
  -H 'Content-Type: application/json' \
  -d @policy.json

# Create alert rule
curl -X POST https://grafana.example.com/api/v1/provisioning/alert-rules \
  -H 'Authorization: Bearer <token>' \
  -H 'Content-Type: application/json' \
  -d @rule.json
```

## Notification Templates

```
# Custom Slack template
{{ define "slack.custom.title" }}
  [{{ .Status | toUpper }}{{ if eq .Status "firing" }}:{{ .Alerts.Firing | len }}{{ end }}]
  {{ .CommonLabels.alertname }}
{{ end }}

{{ define "slack.custom.text" }}
{{ range .Alerts }}
*Alert:* {{ .Annotations.summary }}
*Severity:* {{ .Labels.severity }}
*Service:* {{ .Labels.service }}
*Details:* {{ .Annotations.description }}
{{ if .Annotations.runbook_url }}*Runbook:* {{ .Annotations.runbook_url }}{{ end }}
{{ end }}
{{ end }}
```

## References

- [Alerting Rules](references/alerting.md)
- [IRM & On-Call](references/irm.md)
- [SLOs](references/slo.md)
