# dpm-finder CLI flags

| Flag | Default | Description |
|------|---------|-------------|
| `-f`, `--format` | `csv` | Output format: `csv`, `text`, `txt`, `json`, `prom` |
| `-m`, `--min-dpm` | `1.0` | Minimum DPM threshold to include a metric |
| `-t`, `--threads` | `10` | Concurrent processing threads |
| `-l`, `--lookback` | `10` | Lookback window in minutes |
| `--timeout` | `60` | API request timeout (s). Bump to 120+ for large stacks. |
| `--cost-per-1000-series` | _(none)_ | Adds `estimated_cost` column |
| `-q`, `--quiet` | `false` | Suppress progress output |
| `-v`, `--verbose` | `false` | Debug logging |
| `-e`, `--exporter` | `false` | Run as Prometheus exporter |
| `-p`, `--port` | `9966` | Exporter port |
| `-u`, `--update-interval` | `86400` | Exporter refresh interval (s) |

## Output formats

Files write to the current working directory.

- `csv` → `metric_rates.csv` — columns: `metric_name`, `dpm`, `series_count` (+ `estimated_cost` if priced)
- `json` → `metric_rates.json` — includes `series_detail[]` per-label DPM breakdown + `performance_metrics`
- `text` → `metric_rates.txt` — human-readable
- `prom` → `metric_rates.prom` — Prometheus exposition for Alloy textfile collector

## Exporter mode

```bash
./dpm-finder.py -e -p 9966 -u 86400
```

Serves `http://localhost:PORT/metrics`, recalculates every `-u` seconds.

## Docker

```bash
docker build -t dpm-finder:latest .
docker run --rm --env-file .env -v $(pwd)/output:/app/output \
  dpm-finder:latest --format json --min-dpm 2.0
```

## Auto-excluded metrics

- Histogram/summary components: `*_count`, `*_bucket`, `*_sum`
- Grafana internals: `grafana_*` prefix
- Anything with aggregation rules defined in the cluster (HTTP 422 → skipped + logged)

## Retry behavior

Exponential backoff up to 10 retries; HTTP 429 backed off automatically; other 4xx not retried.
