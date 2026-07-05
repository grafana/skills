# Synthetic Monitoring Reference

## Check Types

| Type | Protocol | Use Case |
|------|----------|----------|
| **HTTP** | HTTP/HTTPS | Website/API uptime and response validation |
| **DNS** | DNS | Record resolution and lookup time |
| **TCP** | TCP | Port/service reachability |
| **Ping** | ICMP | Host availability |
| **MultiHTTP** | HTTP/HTTPS | Multi-step API flows (login, then action) |
| **Browser** (k6) | Chrome | Full browser page load, Core Web Vitals |
| **Scripted** (k6) | k6 script | Custom JS test logic |

## HTTP Check Fields

```json
{
  "job": "api-health",
  "target": "https://api.example.com/health",
  "frequency": 60000,
  "timeout": 15000,
  "enabled": true,
  "probes": [1, 2, 5, 10, 14],
  "settings": {
    "http": {
      "method": "GET",
      "ipVersion": "V4",
      "noFollowRedirects": false,
      "tlsConfig": {
        "insecureSkipVerify": false,
        "serverName": "api.example.com"
      },
      "validStatusCodes": [200],
      "validHTTPVersions": ["HTTP/1.1", "HTTP/2.0"],
      "failIfBodyMatchesRegexp": ["error", "exception"],
      "failIfBodyNotMatchesRegexp": [],
      "failIfHeaderMatchesRegexp": [],
      "failIfHeaderNotMatchesRegexp": [],
      "headers": [
        {"name": "Authorization", "value": "Bearer token"},
        {"name": "User-Agent", "value": "Grafana-SM/1.0"}
      ],
      "body": "",
      "bearerToken": "",
      "basicAuth": {"username": "", "password": ""}
    }
  },
  "labels": [{"name": "env", "value": "production"}],
  "alertSensitivity": "medium"
}
```

## Probe Locations (Post Feb 2025 AWS Migration)

### Americas (AMER)
| ID | Location |
|----|----------|
| 1 | Columbus, Ohio, USA (AWS us-east-2) |
| 2 | Manassas, Virginia, USA (AWS us-east-1) |
| 14 | Portland, Oregon, USA (AWS us-west-2) |
| 15 | São Paulo, Brazil (AWS sa-east-1) |
| 16 | Montreal, Canada (AWS ca-central-1) |

### Europe, Middle East, Africa (EMEA)
| ID | Location |
|----|----------|
| 5 | Frankfurt, Germany (AWS eu-central-1) |
| 10 | Dublin, Ireland (AWS eu-west-1) |
| 17 | London, UK (AWS eu-west-2) |
| 18 | Paris, France (AWS eu-west-3) |
| 19 | Stockholm, Sweden (AWS eu-north-1) |
| 20 | Milan, Italy (AWS eu-south-1) |
| 21 | Cape Town, South Africa (AWS af-south-1) |
| 22 | Bahrain (AWS me-south-1) |

### Asia Pacific (APAC)
| ID | Location |
|----|----------|
| 3 | Singapore (AWS ap-southeast-1) |
| 4 | Sydney, Australia (AWS ap-southeast-2) |
| 6 | Tokyo, Japan (AWS ap-northeast-1) |
| 7 | Mumbai, India (AWS ap-south-1) |
| 8 | Seoul, South Korea (AWS ap-northeast-2) |
| 9 | Hong Kong (AWS ap-east-1) |
| 11 | Osaka, Japan (AWS ap-northeast-3) |
| 12 | Jakarta, Indonesia (AWS ap-southeast-3) |
| 13 | Melbourne, Australia (AWS ap-southeast-4) |

## Alert Sensitivity Levels

| Level | Probe Success Threshold | For Duration |
|-------|------------------------|--------------|
| `none` | No alerts | - |
| `low` | < 50% probes succeeding | 5 minutes |
| `medium` | < 75% probes succeeding | 5 minutes |
| `high` | < 95% probes succeeding | 5 minutes |

Custom alert override (per-check):
```yaml
# Override per check in Terraform
resource "grafana_synthetic_monitoring_check" "api" {
  ...
  alert_sensitivity = "high"
}
```

## Terraform (Configuration as Code)

```hcl
terraform {
  required_providers {
    grafana = { source = "grafana/grafana" }
  }
}

provider "grafana" {
  sm_access_token = var.sm_access_token
  sm_url          = "https://synthetic-monitoring-api.grafana.net"
}

resource "grafana_synthetic_monitoring_check" "website" {
  job       = "homepage"
  target    = "https://example.com"
  enabled   = true
  frequency = 60000
  timeout   = 15000
  probes    = [1, 5, 10, 14]

  settings {
    http {
      valid_status_codes    = [200]
      valid_http_versions   = ["HTTP/1.1", "HTTP/2.0"]
    }
  }

  labels = {
    environment = "production"
    team        = "platform"
  }
}
```

## Grizzly (YAML as Code)

```yaml
apiVersion: grizzly.grafana.com/v1alpha1
kind: SyntheticMonitoringCheck
metadata:
  name: api-health
spec:
  job: api-health
  target: https://api.example.com/health
  frequency: 60000
  timeout: 10000
  probes: [1, 5, 10]
  settings:
    http:
      method: GET
      validStatusCodes: [200]
```

## Key Metrics

```promql
# Uptime % over 7 days
avg_over_time(probe_success{job="api-health"}[7d]) * 100

# P95 response time by location
histogram_quantile(0.95,
  sum(rate(probe_duration_seconds_bucket{job="api-health"}[5m])) by (le, probe)
)

# DNS lookup time trend
avg(probe_dns_lookup_time_seconds{job="dns-check"}) by (probe)

# TLS certificate days until expiry
(probe_ssl_earliest_cert_expiry{job="api-health"} - time()) / 86400

# Availability by region
avg(probe_success{job="api-health"}) by (probe)
```
