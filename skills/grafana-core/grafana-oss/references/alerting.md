# Grafana Alerting - Detailed Reference

## Overview

Grafana Alerting is a unified alerting system for monitoring metrics and logs across multiple data sources. It fires notifications when conditions are breached.

Key capabilities:
- Query multiple data sources in a single alert rule
- Multi-dimensional alerts (one rule creates many alert instances)
- Flexible notification routing via policies
- Silences and mute timings for planned maintenance
- Alert history and state tracking

---

## Core Concepts

### Alert Rule
Defines what to monitor and when to fire. Contains: queries, a condition (threshold), an evaluation interval, and a pending period.

### Alert Instance
When a rule produces multi-dimensional data, it creates one alert instance per unique label combination. Example: an alert on `cpu_usage{host=~".*"}` creates one instance per host.

### Alert States

| State | Description |
|-------|-------------|
| **Normal** | Query running; condition not met |
| **Pending** | Condition met but pending period not yet elapsed |
| **Firing** | Condition met + pending period elapsed; notifications sent |
| **Resolved** | Previously firing alert returned to normal |
| **No Data** | Query returned no data (configurable behavior) |
| **Error** | Query failed with an error (configurable behavior) |

### Evaluation Group
Alert rules are organized into evaluation groups. All rules in a group share the same evaluation interval and are evaluated sequentially.

### Pending Period
How long the condition must be continuously met before firing.
- `0s` = fire immediately
- `5m` = must be in breach for 5 continuous minutes

### Keep Firing For
How long an alert continues firing after the condition resolves (prevents brief recovery from clearing the alert).

---

## Alert Rule Types

### Grafana-Managed Rules (Recommended)
- Stored in Grafana's database
- Can query any data source
- Support multi-dimensional alerting
- Support expressions (math, reduce, threshold)

### Data Source-Managed Rules (Prometheus/Mimir/Loki)
- Rules stored in the external system
- Evaluated by the external system
- Grafana provides UI to manage them
- Useful when migrating from Prometheus alerting

---

## Creating Grafana-Managed Alert Rules

Navigate to: **Alerting > Alert rules > New alert rule**

### Step 1: Define query and condition

Write one or more queries (labeled A, B, C...).

Example with Prometheus:
```promql
# Query A: CPU usage per host
100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)
```

Expression types you can add after queries:
- **Math**: `$A > 80` or `($A + $B) / 2`
- **Reduce**: Collapse time series to single value (Last, Mean, Sum, Max, Min)
- **Resample**: Change time resolution
- **Classic conditions**: Multiple threshold conditions with AND/OR
- **Threshold**: Set the firing threshold

### Step 2: Set evaluation behavior

| Setting | Description |
|---------|-------------|
| Folder | Organize rules; folder is the RBAC boundary |
| Evaluation group | Group name (all rules share this group's interval) |
| Evaluation interval | How often the rule is evaluated (e.g., 1m) |
| Pending period | How long condition must hold before firing (e.g., 5m) |
| Keep firing for | How long alert stays firing after recovery |

### Step 3: Configure labels and notifications

**Labels** - Key-value pairs attached to alert instances. Used for routing and grouping:
```
severity=critical
team=infrastructure
service=database
environment=production
```

**Annotations** - Context included in notification messages:
```
Summary: CPU usage above 80% on {{ $labels.instance }}
Description: CPU usage is {{ $values.A.Value | humanize }}% on {{ $labels.instance }}
Runbook URL: https://runbooks.company.com/cpu-high
```

**Notification settings**:
- Set a **Contact point** to send directly, bypassing the routing policy tree
- Or leave empty to use the notification policy routing tree

### Step 4: No data and error handling

| Situation | Options |
|-----------|---------|
| No data | Alerting, OK, No Data state, Keep last state |
| Query error | Alerting, OK, Error state, Keep last state |

---

## Contact Points

Contact points are notification destinations.

Navigate to: **Alerting > Contact points**

### Supported integrations

| Integration | Notes |
|-------------|-------|
| Email | Requires SMTP config in grafana.ini |
| Slack | Webhook URL or API token + channel |
| PagerDuty | Integration key |
| OpsGenie | API key |
| VictorOps (Splunk) | API key |
| Microsoft Teams | Incoming webhook URL |
| Discord | Webhook URL |
| Telegram | Bot token + chat ID |
| Webhook | HTTP POST to custom URL |
| Alertmanager | Forward to external Alertmanager |
| Pushover | User key + API token |
| LINE | LINE Notify token |

### Email configuration in grafana.ini
```ini
[smtp]
enabled = true
host = smtp.gmail.com:587
user = alerts@company.com
password = app-password
from_address = alerts@company.com
from_name = Grafana Alerts
```

### Webhook payload format
Grafana POSTs a JSON payload to webhook endpoints:
```json
{
  "receiver": "webhook-receiver",
  "status": "firing",
  "alerts": [
    {
      "status": "firing",
      "labels": { "alertname": "HighCPU", "instance": "server1" },
      "annotations": { "summary": "CPU above 80%" },
      "startsAt": "2024-01-15T10:00:00Z",
      "generatorURL": "http://grafana/alerting/..."
    }
  ],
  "groupLabels": { "alertname": "HighCPU" },
  "externalURL": "http://grafana"
}
```

---

## Notification Policies

Notification policies route alerts to contact points based on label matchers.

Navigate to: **Alerting > Notification policies**

### Default policy
The root policy - all alerts reach here if no specific policy matches.

### Child policies
Add policies that match specific labels:
```
Match labels:
  severity = critical    -> contact: pagerduty
  team = infrastructure  -> contact: slack-infra
  environment = staging  -> contact: email-dev
```

### Policy settings

| Setting | Description |
|---------|-------------|
| Contact point | Where to send matching alerts |
| Continue matching | If true, also evaluate subsequent sibling policies |
| Group by | Labels used for batching alerts into single notifications |
| Group wait | Wait before sending first notification for a new group (default: 30s) |
| Group interval | Wait before sending updates for an existing group (default: 5m) |
| Repeat interval | Wait before re-sending for still-firing alerts (default: 4h) |

### Grouping
When multiple alerts have the same "group by" labels, they are batched into a single notification. This prevents notification storms.

Example:
- 50 hosts alert on HighCPU simultaneously
- Group by: `[alertname, datacenter]`
- Result: 1 notification per datacenter containing all affected hosts

---

## Notification Templates

Customize notification message format using Go templating.

Navigate to: **Alerting > Contact points > Notification templates**

### Built-in variables
```
{{ $labels }}          # Alert labels as map
{{ $values }}          # Query values map
{{ $labels.instance }} # Specific label value
{{ $values.A.Value }}  # Specific query value
{{ $status }}          # firing or resolved
{{ $startsAt }}        # When alert started firing
```

### Example Slack template
```
{{ define "slack_message" }}
{{ if eq .Status "firing" }}:red_circle:{{ else }}:large_green_circle:{{ end }} *{{ .Labels.alertname }}*

*Status:* {{ .Status }}
*Severity:* {{ .Labels.severity }}

{{ range .Alerts }}
*Instance:* {{ .Labels.instance }}
*Value:* {{ .Values.A.Value | humanize }}
*Summary:* {{ .Annotations.summary }}
{{ end }}
{{ end }}
```

### Humanize functions
```
{{ $value | humanize }}           # "12.3k"
{{ $value | humanize1024 }}       # "12.3Ki"
{{ $value | humanizeBytes }}      # "12.3 kB"
{{ $value | humanizeDuration }}   # "3h 2m 1s"
{{ $value | humanizePercentage }} # "12.3%"
```

---

## Silences

Silences temporarily suppress alert notifications without stopping alert evaluation.

Navigate to: **Alerting > Silences**

### Create a silence
1. Click **Add silence**
2. Set start time and end time (or duration)
3. Add label matchers:
   ```
   alertname = HighCPU
   instance =~ ".*staging.*"   # Regex match
   severity != critical         # Negative match
   ```
4. Add a comment explaining why
5. Save

### Use cases
- Planned maintenance windows
- Known issues being investigated
- Silencing noisy alerts during deploys

From a firing alert detail view: click **Silence** to pre-populate label matchers.

---

## Mute Timings

Recurring schedules when notifications are suppressed (unlike silences which are one-time).

Navigate to: **Alerting > Mute timings**

### Example mute timings
```
Name: no-alerts-weekends
  Weekdays: Saturday, Sunday

Name: business-hours-only
  Weekdays: Monday-Friday
  Times: 09:00-17:00
```

Attach to notification policies in the policy settings.

---

## RBAC for Alerting

Default permissions by role:

| Action | Viewer | Editor | Admin |
|--------|--------|--------|-------|
| View alert rules | Yes | Yes | Yes |
| Create/edit alert rules | No | Yes | Yes |
| Delete alert rules | No | No | Yes |
| Manage contact points | No | No | Yes |
| Manage notification policies | No | No | Yes |
| Create silences | No | Yes | Yes |

---

## grafana.ini Alerting Configuration

```ini
[unified_alerting]
# Enable unified alerting (default: true since Grafana 9)
enabled = true

# Maximum alert instances a single rule can produce
max_annotations_to_keep = 100

# Evaluation timeout
evaluation_timeout = 30s

# Minimum evaluation interval (prevent too-frequent evaluation)
min_interval = 10s

[smtp]
# Required for email contact points
enabled = true
host = smtp.example.com:587
```

---

## Common Alert Rule Examples

### CPU usage above threshold
```promql
# Query A
100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)
# Threshold: A > 80
# Pending: 5m
# Labels: severity=warning
```

### Memory usage
```promql
# Query A
(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100
# Threshold: A > 90
```

### HTTP error rate
```promql
# Query A: error requests
sum(rate(http_requests_total{status=~"5.."}[5m]))
# Query B: total requests
sum(rate(http_requests_total[5m]))
# Expression C (Math): $A / $B * 100
# Threshold: C > 5
```

### Disk space
```promql
# Query A
(1 - (node_filesystem_free_bytes{fstype!="tmpfs"} / node_filesystem_size_bytes{fstype!="tmpfs"})) * 100
# Threshold: A > 85
```

### Service down (no data = firing)
```promql
# Query A
up{job="my-service"}
# Threshold: A < 1
# No data handling: Alerting (treat absence as firing)
```

### Loki log error rate
```logql
# Query A
sum(rate({job="api"} |= "ERROR" [5m]))
# Threshold: A > 10
```

---

## Connecting Alerts to Dashboards

### Create alert from panel
1. Open panel editor
2. Click **Alert** tab
3. Click **Create alert rule from this panel**
4. Pre-populates query from the panel

### Link alert to dashboard panel
In the alert rule definition, set **Dashboard** and **Panel** to link to a specific visualization. The alert state badge appears on the panel and clicking it goes to the alert rule.

---

## High Availability (HA) Alerting

```ini
[unified_alerting]
ha_peers = grafana-1:9094,grafana-2:9094,grafana-3:9094
ha_advertise_address = ${POD_IP}:9094
ha_peer_timeout = 15s
ha_gossip_interval = 200ms
ha_push_pull_interval = 60s
```

Multiple Grafana instances share state to avoid duplicate notifications.
