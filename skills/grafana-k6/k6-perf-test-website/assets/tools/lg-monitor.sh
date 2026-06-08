#!/usr/bin/env bash
# Load-generator resource sidecar -- cross-platform (macOS + Linux).
#
# Samples k6 / Chromium / system CPU / NIC throughput every $INTERVAL seconds
# (default 5) and writes a CSV row to stdout. Terminate with SIGINT or SIGTERM.
#
# Required because a CPU-pegged load generator silently throttles its own
# request rate -- the server then looks slower than it really is. See the
# k6-perf-test-website skill's lg-monitoring.md.
#
# Usage (standalone):
#   tools/lg-monitor.sh > /tmp/lg.csv &
#   MON=$!; trap "kill $MON" EXIT
#   k6 run tests/...
#
# Usually invoked indirectly via tools/run-with-monitor.sh.
#
# Windows: run under WSL2.

set -u

INTERVAL="${INTERVAL:-5}"
OS="$(uname -s)"

# --- OS-specific functions ------------------------------------------------------

case "$OS" in
  Darwin)
    detect_nic() {
      route get default 2>/dev/null | awk '/interface:/{print $2; exit}'
    }
    sample_cpu() {
      # macOS `top -l 1 -s 0`: "CPU usage: 12.34% user, 5.67% sys, 81.99% idle"
      top -l 1 -s 0 -n 0 2>/dev/null \
        | awk -F'[ %,]+' '/CPU usage:/{print $3 "," $5 "," $7; exit}'
    }
    sample_nic_bytes() {
      # `netstat -ibn`: pick the link row (column 3 contains "Link") for our NIC.
      # Columns: Name Mtu Network Address Ipkts Ierrs Ibytes Opkts Oerrs Obytes ...
      local nic="$1"
      netstat -ibn 2>/dev/null \
        | awk -v nic="$nic" '$1==nic && $3 ~ /Link/{print $7","$10; exit}'
    }
    find_chrome_pids() {
      # macOS: ps -axo pid,command. --headless flag distinguishes test chromium
      # from the user's regular Chrome.
      ps -axo pid=,command= 2>/dev/null \
        | awk 'BEGIN{IGNORECASE=1} /--headless/ && tolower($0) ~ /chrom/ {print $1}' \
        | head -50
    }
    ;;
  Linux)
    detect_nic() {
      # `ip route show default` → "default via X dev eth0 ..."
      ip route show default 2>/dev/null | awk '/^default/{for(i=1;i<=NF;i++)if($i=="dev"){print $(i+1); exit}}'
    }
    sample_cpu() {
      # Read /proc/stat twice (separated by 1s), compute deltas. cpu line:
      # cpu user nice system idle iowait irq softirq steal guest guest_nice
      local a b
      a=$(awk '/^cpu /{print $2","$3","$4","$5","$6","$7","$8","$9; exit}' /proc/stat)
      sleep 1
      b=$(awk '/^cpu /{print $2","$3","$4","$5","$6","$7","$8","$9; exit}' /proc/stat)
      awk -v a="$a" -v b="$b" 'BEGIN {
        n=split(a,aa,",");           split(b,bb,",");
        for (i=1;i<=n;i++) d[i]=bb[i]-aa[i];
        total=0; for (i=1;i<=n;i++) total += d[i];
        if (total==0) { print "0.0,0.0,0.0"; exit }
        user = 100 * (d[1] + d[2]) / total;
        sys  = 100 * (d[3] + d[6] + d[7]) / total;
        idle = 100 * (d[4] + d[5]) / total;
        printf "%.2f,%.2f,%.2f", user, sys, idle;
      }'
    }
    sample_nic_bytes() {
      # /proc/net/dev:
      # iface: rx_bytes packets errs drop fifo frame compressed multicast tx_bytes packets errs ...
      local nic="$1"
      awk -F'[: ]+' -v nic="$nic" '$2==nic{print $3","$11; exit; }; $1==nic{print $2","$10; exit}' \
        < /proc/net/dev
    }
    find_chrome_pids() {
      ps -eo pid=,cmd= 2>/dev/null \
        | awk 'BEGIN{IGNORECASE=1} /--headless/ && tolower($0) ~ /chrom/ {print $1}' \
        | head -50
    }
    ;;
  *)
    echo "lg-monitor: unsupported OS '$OS'. Supported: Darwin (macOS), Linux. Run under WSL2 on Windows." >&2
    exit 2
    ;;
esac

# Detect primary NIC.
NIC="$(detect_nic)"
NIC="${NIC:-en0}"

# --- CSV header ------------------------------------------------------------------

echo "timestamp_iso,uptime_s,sys_cpu_user,sys_cpu_sys,sys_cpu_idle,k6_cpu,k6_mem_pct,k6_rss_kb,chrome_cpu_total,chrome_mem_pct_total,chrome_rss_kb_total,chrome_proc_count,nic,nic_rx_bytes,nic_tx_bytes,nic_rx_bytes_per_s,nic_tx_bytes_per_s"

start_s=$(date +%s)
prev_rx=""
prev_tx=""

trap 'exit 0' INT TERM

# --- Sample loop -----------------------------------------------------------------

while true; do
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  uptime=$(( $(date +%s) - start_s ))

  # System CPU
  cpu_csv="$(sample_cpu)"
  sys_user="$(echo "$cpu_csv" | cut -d, -f1)"
  sys_sys="$(echo  "$cpu_csv" | cut -d, -f2)"
  sys_idle="$(echo "$cpu_csv" | cut -d, -f3)"

  # k6 process (pgrep matches `k6 run ...` invocation).
  # `|| true` is intentional: pgrep exits non-zero with no output when there's
  # no match, which is the normal case during sidecar startup (we sample before
  # k6 starts) and shutdown. Without the guard, callers that source this script
  # under `set -e` (or `bash -e`) silently exit at the first idle sample, and
  # the CSV stops growing -- leading to the false "no monitor output" symptom.
  k6_pid=$(pgrep -fn "k6 run " 2>/dev/null | head -1 || true)
  if [ -n "${k6_pid:-}" ]; then
    k6_line=$(ps -o '%cpu=,%mem=,rss=' -p "$k6_pid" 2>/dev/null | tr -s ' ')
    k6_cpu=$(echo "$k6_line" | awk '{print $1}')
    k6_mem=$(echo "$k6_line" | awk '{print $2}')
    k6_rss=$(echo "$k6_line" | awk '{print $3}')
  else
    k6_cpu=""; k6_mem=""; k6_rss=""
  fi

  # Chromium headless processes (sum across all matching).
  # `|| true` for same reason as the k6 pgrep above -- no match is normal.
  chrome_pids="$(find_chrome_pids || true)"
  chrome_cnt=0
  chrome_cpu=0
  chrome_mem=0
  chrome_rss=0
  if [ -n "${chrome_pids:-}" ]; then
    for p in $chrome_pids; do
      line=$(ps -o '%cpu=,%mem=,rss=' -p "$p" 2>/dev/null | tr -s ' ')
      [ -z "$line" ] && continue
      cpu=$(echo "$line" | awk '{print $1}')
      mem=$(echo "$line" | awk '{print $2}')
      rss=$(echo "$line" | awk '{print $3}')
      chrome_cpu=$(awk "BEGIN{print $chrome_cpu + $cpu}")
      chrome_mem=$(awk "BEGIN{print $chrome_mem + $mem}")
      chrome_rss=$(awk "BEGIN{print $chrome_rss + $rss}")
      chrome_cnt=$((chrome_cnt + 1))
    done
  fi
  if [ "$chrome_cnt" -eq 0 ]; then
    chrome_cpu=""; chrome_mem=""; chrome_rss=""
  fi

  # NIC throughput
  nic_csv="$(sample_nic_bytes "$NIC")"
  rx="$(echo "$nic_csv" | cut -d, -f1)"
  tx="$(echo "$nic_csv" | cut -d, -f2)"
  if [ -n "${prev_rx:-}" ] && [ -n "$rx" ]; then
    rx_per_s=$(awk "BEGIN{print ($rx - $prev_rx) / $INTERVAL}")
    tx_per_s=$(awk "BEGIN{print ($tx - $prev_tx) / $INTERVAL}")
  else
    rx_per_s=""; tx_per_s=""
  fi
  prev_rx="$rx"
  prev_tx="$tx"

  echo "$ts,$uptime,$sys_user,$sys_sys,$sys_idle,$k6_cpu,$k6_mem,$k6_rss,$chrome_cpu,$chrome_mem,$chrome_rss,$chrome_cnt,$NIC,$rx,$tx,$rx_per_s,$tx_per_s"
  sleep "$INTERVAL"
done
