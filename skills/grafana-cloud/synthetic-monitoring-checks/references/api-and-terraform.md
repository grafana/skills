# Synthetic Monitoring checks as code — API and Terraform

## API authentication

Two things are needed (both from **Testing & synthetics → Synthetics → Config**):

- **Access token** — Config → *Access tokens* tab → Generate access token.
- **Backend address** — Config → *General* tab, "Your backend address is", e.g.
  `synthetic-monitoring-api-us-east-0.grafana.net`. It is region-specific to your stack.

```bash
SM_API="https://synthetic-monitoring-api-us-east-0.grafana.net"  # your backend address
SM_TOKEN="<sm-access-token>"
```

Full endpoint list: OpenAPI spec at `https://synthetic-monitoring-api.grafana.net/api/v1/swagger`.

## Check endpoints

| Operation | Endpoint |
|---|---|
| List checks | `GET /api/v1/check` |
| Create check | `POST /api/v1/check` |
| Get check | `GET /api/v1/check/{id}` |
| Update check | `POST /api/v1/check/{id}` (send the full check object incl. `id` and `tenantId`) |
| Delete check | `DELETE /api/v1/check/{id}` |
| Run once without saving | `POST /api/v1/check/adhoc` |
| List probes (get IDs for `probes`) | `GET /api/v1/probe` |

API payload gotchas (differ from the UI):

- `frequency` and `timeout` are in **milliseconds** (UI shows seconds).
- `settings.scripted.script` and `settings.browser.script` are **base64-encoded**
  (`format: byte` in the OpenAPI spec). Plain-text scripts are rejected or corrupted.
- `probes` is an array of numeric probe IDs — resolve names via `GET /api/v1/probe`.

## Create a scripted check

```bash
jq -n --rawfile script check.js '{
  job: "checkout-flow",
  target: "checkout-flow",
  enabled: true,
  frequency: 300000,
  timeout: 90000,
  probes: [1, 5],
  labels: [{ name: "env", value: "production" }],
  settings: { scripted: { script: ($script | @base64) } }
}' | curl -sS -X POST "$SM_API/api/v1/check" \
  -H "Authorization: Bearer $SM_TOKEN" \
  -H "Content-Type: application/json" \
  -d @-
```

A browser check is identical except for the settings key:
`settings: { browser: { script: ($script | @base64) } }` (and remember browser
executions are billed at the browser rate).

## Create a MultiHTTP check

MultiHTTP assertions use numeric enums in the API (the UI hides this). Enum values, from
the [check protobuf definition](https://github.com/grafana/synthetic-monitoring-agent/blob/main/pkg/pb/synthetic_monitoring/checks.proto):

| Field | Values |
|---|---|
| `checks[].type` | 0 TEXT · 1 JSON_PATH_VALUE · 2 JSON_PATH_ASSERTION · 3 REGEX_ASSERTION |
| `checks[].subject` | 0 DEFAULT (body) · 1 RESPONSE_HEADERS · 2 HTTP_STATUS_CODE · 3 RESPONSE_BODY |
| `checks[].condition` | 1 NOT_CONTAINS · 2 EQUALS · 3 STARTS_WITH · 4 ENDS_WITH · 5 TYPE_OF · 6 CONTAINS |
| `variables[].type` | 0 JSON_PATH · 1 REGEX · 2 CSS_SELECTOR |

Minimal two-request example — POST for a token, then use it (each request asserts
status 200: TEXT assertion on HTTP_STATUS_CODE EQUALS "200"):

```bash
curl -sS -X POST "$SM_API/api/v1/check" \
  -H "Authorization: Bearer $SM_TOKEN" -H "Content-Type: application/json" -d '{
  "job": "api-flow",
  "target": "https://api.example.com/auth",
  "enabled": true,
  "frequency": 120000,
  "timeout": 30000,
  "probes": [1, 5],
  "settings": {
    "multihttp": {
      "entries": [
        {
          "request": { "method": "POST", "url": "https://api.example.com/auth" },
          "checks": [
            { "type": 0, "subject": 2, "condition": 2, "value": "200" }
          ],
          "variables": [
            { "type": 0, "name": "token", "expression": "$.token" }
          ]
        },
        {
          "request": {
            "method": "GET",
            "url": "https://api.example.com/orders",
            "headers": [{ "name": "Authorization", "value": "Bearer ${token}" }]
          },
          "checks": [
            { "type": 0, "subject": 2, "condition": 2, "value": "200" }
          ]
        }
      ]
    }
  }
}'
```

For complex MultiHTTP checks, the safest path is to build one in the UI and
`GET /api/v1/check/{id}` to copy its JSON.

Remember: MultiHTTP requests without `checks` entries do not affect uptime — always
assert at least the status code per request.

## Update, disable, delete

```bash
# Fetch, flip enabled=false (rollback without losing config), push back
curl -sS "$SM_API/api/v1/check/123" -H "Authorization: Bearer $SM_TOKEN" \
  | jq '.enabled = false' \
  | curl -sS -X POST "$SM_API/api/v1/check/123" \
      -H "Authorization: Bearer $SM_TOKEN" -H "Content-Type: application/json" -d @-

# Delete permanently
curl -sS -X DELETE "$SM_API/api/v1/check/123" -H "Authorization: Bearer $SM_TOKEN"
```

## Terraform

`grafana_synthetic_monitoring_check` takes the plain script (the provider handles
encoding). `frequency`/`timeout` are milliseconds, `probes` is required, and probe IDs
resolve via the probes data source.

```hcl
terraform {
  required_providers {
    grafana = {
      source  = "grafana/grafana"
      version = "~> 4.0"
    }
  }
}

variable "sm_access_token" {
  type      = string
  sensitive = true
}

provider "grafana" {
  sm_access_token = var.sm_access_token
  sm_url          = "https://synthetic-monitoring-api-us-east-0.grafana.net" # your backend address
}

data "grafana_synthetic_monitoring_probes" "main" {}

# Simplest sufficient type first: a plain HTTP check needs no script at all.
resource "grafana_synthetic_monitoring_check" "api_health" {
  job       = "api-health"
  target    = "https://api.example.com/health"
  enabled   = true
  frequency = 60000 # ms
  timeout   = 5000  # ms
  probes = [
    data.grafana_synthetic_monitoring_probes.main.probes.Ohio,
    data.grafana_synthetic_monitoring_probes.main.probes.Frankfurt,
  ]

  settings {
    http {
      method              = "GET"
      valid_status_codes  = [200]
      valid_http_versions = ["HTTP/1.1", "HTTP/2.0"]
      fail_if_not_ssl     = true
    }
  }
}

resource "grafana_synthetic_monitoring_check" "checkout_flow" {
  job       = "checkout-flow"
  target    = "checkout-flow"
  enabled   = true
  frequency = 300000 # ms — every 5 minutes
  timeout   = 90000  # ms — must cover the whole journey (max 180000)
  probes = [
    data.grafana_synthetic_monitoring_probes.main.probes.Ohio,
    data.grafana_synthetic_monitoring_probes.main.probes.Frankfurt,
  ]
  labels = {
    env = "production"
  }

  settings {
    scripted {
      script = file("${path.module}/scripts/checkout-flow.js")
    }
  }
}

resource "grafana_synthetic_monitoring_check" "login_journey_browser" {
  job       = "login-journey"
  target    = "https://shop.example.com/login"
  enabled   = true
  frequency = 600000 # ms — browser executions are the expensive tier; be deliberate
  timeout   = 120000 # ms
  probes = [
    data.grafana_synthetic_monitoring_probes.main.probes.Ohio,
  ]

  settings {
    browser {
      script = file("${path.module}/scripts/login-journey.js")
    }
  }
}
```

Terraform is also the standard workaround for bundled/minified browser scripts that the
UI's import validation rejects.

### MultiHTTP in Terraform

Unlike the API, Terraform takes the assertion and variable enums as **strings**
(`TEXT`, `HTTP_STATUS_CODE`, `EQUALS`, `JSON_PATH`, ...) — same names as the protobuf,
no numbers needed:

```hcl
resource "grafana_synthetic_monitoring_check" "api_flow" {
  job       = "api-flow"
  target    = "https://api.example.com/auth"
  frequency = 120000
  timeout   = 30000
  probes    = [data.grafana_synthetic_monitoring_probes.main.probes.Ohio]

  settings {
    multihttp {
      entries {
        request {
          method = "POST"
          url    = "https://api.example.com/auth"
        }
        assertions {
          type      = "TEXT"
          subject   = "HTTP_STATUS_CODE"
          condition = "EQUALS"
          value     = "200"
        }
        variables {
          type       = "JSON_PATH"
          name       = "token"
          expression = "$.token"
        }
      }
      entries {
        request {
          method = "GET"
          url    = "https://api.example.com/orders"
          headers {
            name  = "Authorization"
            value = "Bearer $${token}"
          }
        }
        assertions {
          type      = "TEXT"
          subject   = "HTTP_STATUS_CODE"
          condition = "EQUALS"
          value     = "200"
        }
      }
    }
  }
}
```

(`$${token}` is Terraform escaping for a literal `${token}` — SM interpolates the
variable at probe time.)

### Protocol (blackbox-exporter) checks in Terraform

The simple check types — HTTP, ping, DNS, TCP, traceroute, gRPC — need no script and are
the bulk of most fleets. Two things agents get wrong:

- `settings` must contain **exactly one** nested block, even with all defaults:
  `settings { ping {} }` is valid and required — an empty `settings {}` is not.
- The `target` format differs per type:

| Type | `target` format | Key settings fields |
|---|---|---|
| `http` | Full URL `https://example.com/health` | `valid_status_codes`, `fail_if_not_ssl`, `fail_if_body_not_matches_regexp`, `headers`, `basic_auth` |
| `ping` | Hostname `example.com` | usually none (`ping {}`) |
| `dns` | Record to resolve `example.com` | `server` (default `8.8.8.8`), `record_type` (default `A`), `valid_r_codes`, `validate_answer_rrs` |
| `tcp` | `host:port` `example.com:443` | `tls`, `query_response { send / expect / start_tls }` |
| `traceroute` | Hostname `example.com` | `max_hops`, `max_unknown_hops`, `ptr_lookup` |
| `grpc` | `host:port` | `service` (health-check service name), `tls`, `tls_config` |

```hcl
# DNS: assert the record resolves against your own nameserver with NOERROR
resource "grafana_synthetic_monitoring_check" "dns_www" {
  job       = "dns-www"
  target    = "www.example.com"
  frequency = 120000
  timeout   = 5000
  probes    = [data.grafana_synthetic_monitoring_probes.main.probes.Ohio]

  settings {
    dns {
      server        = "ns1.example.com"
      record_type   = "A"
      valid_r_codes = ["NOERROR"]
    }
  }
}

# TCP with TLS: also feeds probe_ssl_earliest_cert_expiry for cert-expiry alerting
resource "grafana_synthetic_monitoring_check" "smtp" {
  job       = "smtp-tls"
  target    = "mail.example.com:465"
  frequency = 300000
  timeout   = 5000
  probes    = [data.grafana_synthetic_monitoring_probes.main.probes.Frankfurt]
  alert_sensitivity = "high"

  settings {
    tcp {
      tls = true
    }
  }
}

# Ping and traceroute need only the empty block
resource "grafana_synthetic_monitoring_check" "edge_ping" {
  job       = "edge-ping"
  target    = "edge.example.com"
  frequency = 60000
  timeout   = 3000
  probes    = [data.grafana_synthetic_monitoring_probes.main.probes.Ohio]

  settings {
    ping {}
  }
}
```

Other top-level fields worth setting as-code: `alert_sensitivity` (`none` default —
set `low`/`medium`/`high` to feed the prebuilt `probe_success` alert rules) and
`basic_metrics_only` (defaults to `true`; set `false` only if you need the full
blackbox-exporter metric set).

Resource docs: https://registry.terraform.io/providers/grafana/grafana/latest/docs/resources/synthetic_monitoring_check
