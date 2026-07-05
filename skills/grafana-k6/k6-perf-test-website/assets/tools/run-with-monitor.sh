#!/usr/bin/env bash
# Run a k6 script with the LG resource sidecar (lg-monitor.sh).
#
# Required for any test type beyond smoke, so we can tell whether the laptop
# running k6 is the bottleneck rather than the server-under-test. See the
# k6-perf-test-website skill's lg-monitoring.md.
#
# Usage:
#   tools/run-with-monitor.sh tests/wN-<short-name>/smoke.js
#   tools/run-with-monitor.sh tests/wN-<short-name>/stress.js
#   INTERVAL=2 tools/run-with-monitor.sh tests/wN-<short-name>/spike.js   # finer sampling
#
# Writes:
#   /tmp/perf-lg-monitor/<workflow>-<test-type>-<timestamp>.csv      full samples
#   /tmp/perf-lg-monitor/<workflow>-<test-type>-<timestamp>.k6.log   full k6 output
#
# On exit, prints a summary of LG resource usage and a saturation verdict
# (OK / NOTE / WARNING). Treat WARNING runs as inconclusive.

set -u

if [ $# -lt 1 ]; then
  echo "usage: $0 <k6-script-path> [k6-args...]" >&2
  exit 1
fi

K6_SCRIPT="$1"; shift
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Identify workflow + test type from path.
WF=$(basename "$(dirname "$K6_SCRIPT")")
TT=$(basename "$K6_SCRIPT" .js)
TS=$(date +%Y%m%d-%H%M%S)

LOGDIR="/tmp/perf-lg-monitor"
mkdir -p "$LOGDIR"
CSV="$LOGDIR/$WF-$TT-$TS.csv"
K6LOG="$LOGDIR/$WF-$TT-$TS.k6.log"

echo "=== Run: $WF · $TT · $(date +%H:%M:%S) ==="
echo "Monitor CSV: $CSV"
echo "k6 log     : $K6LOG"

# Start monitor in background.
bash "$SCRIPT_DIR/lg-monitor.sh" > "$CSV" &
MON_PID=$!
trap 'kill "$MON_PID" 2>/dev/null; wait "$MON_PID" 2>/dev/null; exit' INT TERM EXIT

# Brief grace so the monitor captures a baseline sample.
sleep 2

# Run k6 (env vars including BASE_URL inherit).
echo "--- k6 starting ---"
k6 run "$K6_SCRIPT" "$@" 2>&1 | tee "$K6LOG"
K6_RC="${PIPESTATUS[0]}"
echo "--- k6 finished (rc=$K6_RC) ---"

# Stop monitor.
kill "$MON_PID" 2>/dev/null
wait "$MON_PID" 2>/dev/null
trap - INT TERM EXIT

# --- Summarise the CSV ----------------------------------------------------------

echo
echo "=== LG monitor summary ==="

if ! command -v python3 >/dev/null 2>&1; then
  echo "(python3 not found; raw CSV at $CSV)"
  exit "$K6_RC"
fi

python3 - "$CSV" <<'PY'
import csv, sys, statistics

def to_f(v):
    try: return float(v)
    except Exception: return None

with open(sys.argv[1]) as f:
    rows = list(csv.DictReader(f))

if len(rows) < 2:
    print("Not enough samples to summarise.")
    sys.exit()

def col(name):
    return [v for r in rows for v in [to_f(r.get(name, ''))] if v is not None]

def stat(vals, fmt='{:.1f}'):
    if not vals: return 'n/a'
    return f"min={fmt.format(min(vals))} avg={fmt.format(statistics.mean(vals))} max={fmt.format(max(vals))}"

duration = rows[-1].get('uptime_s', '?')
try:
    interval = int(rows[1]['uptime_s']) - int(rows[0]['uptime_s'])
except Exception:
    interval = '?'
print(f"samples       : {len(rows)}")
print(f"duration      : {duration}s")
print(f"interval      : {interval}s")
print()
print(f"sys_cpu_idle  : {stat(col('sys_cpu_idle'))}  (lower = laptop more saturated)")
print(f"k6 %CPU       : {stat(col('k6_cpu'))}")
print(f"k6 RSS (MB)   : {stat([v/1024 for v in col('k6_rss_kb')])}")
print(f"chrome %CPU   : {stat(col('chrome_cpu_total'))}")
print(f"chrome RSS MB : {stat([v/1024 for v in col('chrome_rss_kb_total')])}")
print(f"chrome procs  : {stat(col('chrome_proc_count'), '{:.0f}')}")
print(f"NIC rx MB/s   : {stat([v/1e6 for v in col('nic_rx_bytes_per_s')], '{:.2f}')}")
print(f"NIC tx MB/s   : {stat([v/1e6 for v in col('nic_tx_bytes_per_s')], '{:.2f}')}")
print()

# Saturation verdict
idle = col('sys_cpu_idle')
if idle:
    min_idle = min(idle)
    if min_idle < 10:
        print(f"WARNING: system idle dropped to {min_idle:.1f}% -- LG was saturated; k6 numbers unreliable")
    elif min_idle < 30:
        print(f"NOTE: system idle dipped to {min_idle:.1f}% -- LG had headroom but not much")
    else:
        print(f"OK: system idle stayed >= {min_idle:.1f}% -- LG had plenty of headroom")
PY

exit "$K6_RC"
