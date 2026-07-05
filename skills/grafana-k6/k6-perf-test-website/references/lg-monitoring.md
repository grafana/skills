# Load-generator monitoring (LG sidecar)

## Why this exists

A load generator that runs out of CPU, memory, or NIC bandwidth
**silently throttles its own request rate**. The k6 results then
show:

- Lower-than-expected request rate (looks like the server is slow).
- Higher-than-expected latency (because k6 itself is slow to enqueue
  the next request, not because the response is slow).
- "Iterations interrupted" with cryptic timeout messages.

Without an LG monitor running alongside k6, you cannot distinguish
"server is slow" from "laptop is at 100% CPU and k6 is queueing
its own work".

**Rule: any test type beyond smoke must run with the monitor
sidecar.** The smoke is short enough that LG saturation is
unlikely; everything else can hit it.

## What the sidecar samples

At a fixed interval (default 5s), one CSV row containing:

| Column                    | Why                                     |
|---------------------------|-----------------------------------------|
| timestamp_iso, uptime_s   | timeline                                |
| sys_cpu_user/sys/idle     | system-wide CPU; idle is the headline   |
| k6_cpu / k6_mem / k6_rss  | the k6 process itself                   |
| chrome_cpu_total / mem / rss / proc_count | browser VU footprint    |
| nic_rx_bytes / nic_tx_bytes / per_s     | network throughput        |

The post-run summary computes min/avg/max for the headline columns
and emits a verdict.

## Verdict thresholds

The bundled `run-with-monitor.sh` emits:

- **OK**: minimum `sys_cpu_idle ≥ 30%`. LG had plenty of headroom.
- **NOTE**: 10% ≤ min idle < 30%. LG had headroom but not much.
- **WARNING**: min idle < 10%. LG was saturated; k6 numbers are
  unreliable.

When you see WARNING, treat the run as **inconclusive** and either:

- Reduce VUs and re-run.
- Move the test type to cloud (revisit elicitation §1).
- Split the test across multiple LGs.

Do **not** report findings derived from a WARNING run.

## How chromium is detected

The sidecar identifies test-spawned Chromium processes by the
`--headless` flag on their command line. The user's regular
Chrome (browsing real websites in another window) does **not**
have that flag, so it is excluded from the chromium-process count.

If you launch k6/browser with `K6_BROWSER_HEADLESS=false` for
debugging, the sidecar will not see the chromium processes and
the chromium columns will be empty.

## Cross-platform notes

The bundled script uses `uname -s` to branch between macOS and
Linux command syntax:

- **CPU**: macOS uses `top -l 1 -s 0`; Linux uses `top -bn1` or
  `mpstat 1 1` if available.
- **NIC**: macOS uses `netstat -ib`; Linux reads
  `/proc/net/dev` or `ip -s link`.
- **Default route**: macOS `route get default`; Linux `ip route
  show default`.

Windows is not supported directly — run the skill from WSL2 instead.

## Reading a monitor CSV

If you want to drill in past the summary:

```bash
# Quick view of saturation timeline
awk -F, 'NR==1{print; next} $5 != "" {print $1, $5}' \
    /tmp/perf-lg-monitor/wN-stress-*.csv

# Max chromium RSS over the run
awk -F, 'NR>1 && $11 != "" {print $11}' \
    /tmp/perf-lg-monitor/wN-soak-*.csv | sort -n | tail -1
```

For a long soak run, plotting `k6_rss_kb` over time is more
revealing than the min/avg/max summary — a steady upward slope is
the signal of accumulation (whether real leak or client-side
metric accumulation; see gotchas).

## Limitations

- Process metrics are sampled, not integrated. A short CPU spike
  between samples can be missed. Lower `INTERVAL` (e.g. `INTERVAL=2`)
  for spike tests where bursts matter.
- NIC bytes are measured at the interface level — VPN tunnels and
  loopback are not visible. If you run k6 against `localhost`, the
  NIC counters will be ~0.
- The sidecar adds <1% overhead but is not free. Don't extrapolate
  millisecond-precision timings from sidecar-instrumented runs.

## Integration with k6 cloud runs

The sidecar only helps for **local** runs. Cloud k6 runs LGs in
Grafana's infrastructure; the LG monitor doesn't see them.

For cloud runs:

- LG load is automatically tracked by Grafana Cloud k6.
- Inspect the LG utilisation panels in the cloud test run UI to
  confirm cloud LGs themselves were not the bottleneck.
