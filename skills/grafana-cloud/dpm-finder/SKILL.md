---
name: dpm-finder
license: Apache-2.0
description: Find the Prometheus metrics that drive your Grafana Cloud bill. `dpm-finder` is a Grafana Professional Services CLI that ranks metrics by Data Points per Minute (DPM) with per-label-set breakdown, optional `--cost-per-1000-series` pricing, and a Prometheus-exporter mode. Use when investigating high Grafana Cloud spend, hunting noisy / high-cardinality metrics, comparing pre/post recording-rule cardinality, or feeding cost data into dashboards — even when the user says "why is my Mimir bill so high?", "find the biggest metrics", "cardinality offenders", or "optimize Prometheus cost" without naming dpm-finder.
---

# dpm-finder

Grafana PS tool ranking Prometheus metrics by DPM with per-series breakdown. Source: https://github.com/grafana-ps/dpm-finder

## Prerequisites

- Python 3.9+
- A Grafana Cloud Prometheus endpoint URL + numeric stack ID + API key (`glc_…`, `metrics:read` scope)

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
- Sort by DPM descending → noisiest metrics; combine with `--cost-per-1000-series` to prioritize by spend

## Troubleshooting

- **401 / 403** — API key invalid or missing `metrics:read`; confirm `PROMETHEUS_USERNAME` is the numeric stack ID
- **Timeouts** — bump `--timeout` to 120+ for stacks with thousands of metrics
- **HTTP 422** — metric has aggregation rules; tool warns + skips automatically
- **Empty results** — lower `-m`; verify endpoint has no trailing path
- **Connection errors** — exponential backoff retries up to 10 times; persistent failure usually = network/firewall

## References

- [`references/cli.md`](references/cli.md) — full flag reference, output-format details, exporter mode, Docker invocation, auto-exclusion rules, retry behavior

## Resources

- [dpm-finder GitHub](https://github.com/grafana-ps/dpm-finder)
- [gcx](https://github.com/grafana/gcx)
