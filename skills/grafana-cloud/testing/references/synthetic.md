# Synthetic Monitoring — check types, metrics, alerts

## Check types

| Check | Use case |
|-------|----------|
| **HTTP** | Website / API availability, response validation |
| **DNS** | DNS resolution time + record validation |
| **TCP** | Port / service connectivity |
| **Ping** | ICMP availability |
| **Traceroute** | Network path diagnostics |
| **Multihttp** | Multi-step HTTP flows |
| **Scripted** (k6 browser) | Full browser-based user-flow testing |

## HTTP check (full API payload)

```bash
curl -X POST https://synthetic-monitoring-api.grafana.net/sm/checks \
  -H "Authorization: Bearer <sm-access-token>" \
  -H "Content-Type: application/json" \
  -d '{
    "job": "website",
    "target": "https://example.com",
    "frequency": 60000,
    "timeout": 15000,
    "enabled": true,
    "probes": [1, 5, 10],
    "settings": {
      "http": {
        "method": "GET",
        "ipVersion": "V4",
        "noFollowRedirects": false,
        "tlsConfig": {},
        "validStatusCodes": [200, 201],
        "validHTTPVersions": ["HTTP/1.1", "HTTP/2.0"],
        "failIfBodyMatchesRegexp": ["error", "exception"],
        "failIfBodyNotMatchesRegexp": ["OK"],
        "headers": [{"name": "User-Agent", "value": "Grafana-Synthetic-Monitoring"}]
      }
    }
  }'
```

## Useful PromQL

```promql
# Probe success rate
sum(rate(probe_success[5m])) by (job, instance, probe)

# HTTP response time p95
histogram_quantile(0.95, sum(rate(probe_duration_seconds_bucket[5m])) by (le, job))

# DNS lookup time
avg(probe_dns_lookup_time_seconds) by (job, instance)

# TLS expiry days remaining
(probe_ssl_earliest_cert_expiry - time()) / 86400
```

## Alert rules

```yaml
groups:
  - name: synthetic-monitoring
    rules:
      - alert: SyntheticCheckFailing
        expr: avg_over_time(probe_success[5m]) < 0.9
        for: 5m
        labels: { severity: critical }
        annotations:
          summary: "{{ $labels.job }} failing from {{ $labels.probe }}"

      - alert: TLSCertExpiringSoon
        expr: (probe_ssl_earliest_cert_expiry - time()) / 86400 < 14
        labels: { severity: warning }
        annotations:
          summary: "TLS cert for {{ $labels.instance }} expires in {{ $value }} days"
```
