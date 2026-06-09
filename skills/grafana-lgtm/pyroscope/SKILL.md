---
name: pyroscope
license: Apache-2.0
description: Continuously profile applications with Grafana Pyroscope and read the result as flame graphs. Covers three instrumentation paths — language SDK push (Go / Java / Python / Ruby / Node / .NET / Rust), Alloy eBPF auto-instrumentation (no code change, requires kernel 5.8+ with BTF), and SDK → Alloy receiver — plus ProfileQL queries, profile types (CPU / memory / allocations / goroutines / mutex), Grafana Cloud Profiles endpoint, and Span Profiles trace-to-profile linking. Use when adding profiling to a service, deploying Alloy as a cluster-wide eBPF profiler, hunting CPU / memory hotspots from a flame graph, comparing two profiles to find a regression, or correlating a slow Tempo trace to its profile — even when the user says "find what's burning CPU", "flame graph this app", "continuous profiling", "heap hotspots", or "why is allocation so high" without naming Pyroscope.
---

# Grafana Pyroscope

> **Docs**: https://grafana.com/docs/pyroscope/latest/

Continuous profiling — flame graphs of CPU, memory, allocations, mutex contention, goroutines.

## Prerequisites

- Pyroscope server (OSS) or Grafana Cloud Profiles endpoint
- For Cloud: numeric Pyroscope user (stack id) + API key
- For eBPF via Alloy: root + host PID + Linux ≥ 5.8 with BTF (or RHEL 4.18+)

## Instrumentation paths

1. **Alloy eBPF** (preferred) — auto-instrument, no code change
2. **SDK direct push** — application calls Pyroscope API
3. **SDK → Alloy** — SDK posts to `pyroscope.receive_http`, Alloy forwards

## Common Workflows

### 1. Instrument an app with the SDK (representative: Python)

```bash
pip install pyroscope-io==1.0.11
```

```python
import pyroscope, os
pyroscope.configure(
    application_name="my.python.app",
    server_address="http://pyroscope:4040",
    sample_rate=100, oncpu=True,
    tags={"region": os.getenv("REGION"), "env": "prod"},
)
# Dynamic tag for a hot path
with pyroscope.tag_wrapper({"controller": "slow_controller"}):
    slow_code()
```

```bash
# Verify the app is pushing — Pyroscope ingests samples in a few seconds
curl -s http://pyroscope:4040/ready                                    # → "ready"
curl -s http://pyroscope:4040/api/v1/labels | jq '.data | index("service_name")'  # → not null

# Verify the service shows up in Grafana → Explore → Profiles → service dropdown.
```

Other SDKs (Java agent, Node, Ruby, .NET, Rust) + Cloud auth + tunable env vars: [`references/sdks.md`](references/sdks.md).

### 2. Cluster-wide eBPF profiling with Alloy

```alloy
# config.alloy — full block in references/ebpf-and-query.md
pyroscope.ebpf "local_pods" {
  forward_to       = [pyroscope.write.cloud.receiver]
  targets          = discovery.relabel.local_pods.output
  sample_rate      = 97
  collect_interval = "15s"
}
pyroscope.write "cloud" {
  endpoint {
    url = "https://profiles-prod-xxx.grafana.net"
    basic_auth { username = sys.env("PYROSCOPE_USER")
                 password = sys.env("GRAFANA_API_KEY") }
  }
}
```

```bash
# 1. Reload Alloy
curl -X POST http://localhost:12345/-/reload

# 2. Verify the eBPF component is healthy
curl -s http://localhost:12345/api/v0/web/components \
  | jq '.[] | select(.id|contains("pyroscope.ebpf")) | {id,health:.health.state}'
# Expect: health.state == "healthy"

# 3. Verify profiles arriving in Pyroscope
#    Grafana → Explore → Profiles datasource → query:
#      {namespace="default", __profile_type__="process_cpu:cpu:nanoseconds:cpu:nanoseconds"}
#    Expect flame graph to render with frames from the target pods.
```

### 3. Query with ProfileQL

```
{service_name="myapp", env="prod",
 __profile_type__="process_cpu:cpu:nanoseconds:cpu:nanoseconds"}
```

Profile-type list + full ProfileQL grammar: [`references/ebpf-and-query.md`](references/ebpf-and-query.md).

## Troubleshooting

- SDK starts but no flame graph → check the app actually called `start()` / `configure()` (some SDKs are lazy); check `server_address` reachable from inside the container
- Alloy eBPF component `unhealthy` with BPF errors → kernel < 5.8 or BTF missing; `ls /sys/kernel/btf/vmlinux`
- Cloud push 401 → wrong `basic_auth_username` (must be the numeric stack id, not the slug)
- Profile shows up but with no frames → for Java, set `PYROSCOPE_FORMAT=jfr`; for Python on Alpine, ensure `procfs` and `glibc` compatibility

## Resources

- [Pyroscope docs](https://grafana.com/docs/pyroscope/latest/)
- [Grafana Cloud Profiles](https://grafana.com/docs/grafana-cloud/monitor-applications/profiles/)
- [`references/sdks.md`](references/sdks.md) — Java/Node/Ruby/.NET/Rust install + config + env-var table + profile-type matrix
- [`references/ebpf-and-query.md`](references/ebpf-and-query.md) — full Alloy eBPF pipeline + ProfileQL
