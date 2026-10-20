---
name: dpm-finder
license: Apache-2.0
description: Find the Prometheus metrics that drive your Grafana Cloud bill. `dpm-finder` is a Grafana Professional Services CLI that ranks metrics by Data Points per Minute (DPM) with per-label-set breakdown, optional `--cost-per-1000-series` pricing, and a Prometheus-exporter mode. Use when investigating high Grafana Cloud spend, hunting noisy / high-cardinality metrics, comparing pre/post recording-rule cardinality, or feeding cost data into dashboards — even when the user says "why is my Mimir bill so high?", "find the biggest metrics", "cardinality offenders", or "optimize Prometheus cost" without naming dpm-finder.
---

# dpm-finder

Modification note (2026-10-11): updated runtime filtering, Adaptive Metrics handling and cost-interpretation guidance.

Grafana PS tool ranking Prometheus metrics by DPM with per-series breakdown. Source: https://github.com/grafana-ps/dpm-finder

## Prerequisites

- Python 3.9+
- A Grafana Cloud Prometheus endpoint URL + numeric stack ID + API key (`glc_…`, `metrics:read` scope)

Current runtimes also use `adaptive-metrics-rules:read` to inspect applied aggregation rules. Without that scope, stored-series discovery and targeted Adaptive Metrics 422 fallback can still work; report unavailable rule evidence rather than requesting broader credentials automatically.

## Common Workflows

### One-shot analysis (most common)

```bash
# 1. Clone + venv + install
git clone https://github.com/grafana-ps/dpm-finder.git
cd dpm-finder
python3 -m venv venv && source venv/bin/activate
pip install -r requirements.txt

# 2. Configure creds — copy .env_example → .env and fill in:
#    PROMETHEUS_ENDPOINT  https://prometheus-<cluster_slug>.grafana.net  (NOTHING after .net)
#    PROMETHEUS_USERNAME  <numeric stack id>
#    PROMETHEUS_API_KEY   glc_…

# 3. Verify creds before scanning — should return >0 series count
curl -s -u "$PROMETHEUS_USERNAME:$PROMETHEUS_API_KEY" \
  "$PROMETHEUS_ENDPOINT/api/v1/label/__name__/values" | jq '.data | length'

# 4. Run the scan (10-min lookback, 2.0 DPM minimum, top output)
./dpm-finder.py -f json -m 2.0 -t 8 --timeout 120 -l 10

# 5. Read the result — top 10 metrics by DPM
jq -r '.metrics | sort_by(-.dpm) | .[:10][] | "\(.dpm)\t\(.series_count)\t\(.metric_name)"' metric_rates.json
```

If step 5 is empty, lower `-m` or confirm the endpoint URL has no trailing path after `.net`.

### Discover stack details with `gcx`

If [gcx](https://github.com/grafana/gcx) is installed it can derive the endpoint + username:

```bash
gcx config check          # active stack context
gcx config list-contexts  # all configured stacks
gcx config view           # full config with endpoints
```

The Prometheus endpoint pattern is `https://prometheus-{cluster_slug}.grafana.net`. Username is the numeric stack ID.

Without gcx: look up in the Grafana Cloud portal, or query `grafanacloud_instance_info{name=~"STACK_NAME.*"}` on the usage datasource.

### Multi-stack runs

Limit to **max 3 concurrent** runs to avoid GCloud rate limits. Batch the stacks and wait for each batch before the next.

## Interpreting results

- **DPM** = max data points per minute across that metric's series
- **series_count** = active time-series count for that metric
- **series_detail[]** (JSON / text only) = per-label-combination DPM breakdown — use this to spot the offending label
- Sorting by `dpm` finds the fastest-sampled individual series, not the metrics with the largest total sample volume. For example, 1,000 series at 1 DPM generate more samples than 10 series at 6 DPM, despite ranking lower on maximum DPM. The configured minimum DPM filter also excludes lower-rate metrics from the result.
- Inspect `series_detail` to sum observed per-series sampling rates when available. Do not treat `max_dpm × series_count` as an exact total when sampling rates differ or series populations change.
- Treat `--cost-per-1000-series` / `estimated_cost` as a diagnostic estimate, not an invoice prediction. Reconcile with the account's included DPM, billing-period usage and current [Grafana metrics pricing methodology](https://grafana.com/docs/grafana-cloud/platform/pricing-and-usage/metrics/).

## Troubleshooting

- **401 / 403** — API key invalid or missing `metrics:read`; confirm `PROMETHEUS_USERNAME` is the numeric stack ID
- **Timeouts** — bump `--timeout` to 120+ for stacks with thousands of metrics
- **Adaptive Metrics HTTP 422** — current runtimes retry explicitly identified aggregated-query errors against stored aggregated series; unrelated 422 responses are logged and skipped
- **Empty results** — lower `-m`; verify endpoint has no trailing path
- **Connection errors** — exponential backoff retries up to 10 times; persistent failure usually = network/firewall

## References

- [`references/cli.md`](references/cli.md) — full flag reference, output-format details, exporter mode, Docker invocation, auto-exclusion rules, retry behavior

## Resources

- [dpm-finder GitHub](https://github.com/grafana-ps/dpm-finder)
- [gcx](https://github.com/grafana/gcx)
