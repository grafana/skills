---
name: beyla
license: Apache-2.0
description: Auto-instrument an application's HTTP / gRPC / DB traffic with Grafana Beyla eBPF — no code changes, no SDK, no restart. Covers requirements (Linux 5.8+ with BTF, CAP_SYS_ADMIN, host PID), language matrix (Go / Java / Python / Ruby / Node / .NET / Rust / C++ / PHP), Docker + Helm + DaemonSet install, port- / process- / Kubernetes-metadata discovery, OTLP traces + Prometheus metrics export, routes decorator (cardinality control), trace sampling, and Grafana Cloud via Alloy. Use when adding observability to a service you can't recompile, instrumenting a closed-source binary, getting RED metrics + spans onto Tempo/Mimir without touching the app, or rolling Beyla as a cluster-wide DaemonSet — even when the user says "zero-code APM", "instrument legacy app", "trace this binary", "eBPF observability", or "no SDK" without naming Beyla.
---

# Grafana Beyla

> **Docs**: https://grafana.com/docs/beyla/latest/

Zero-code HTTP / gRPC / DB instrumentation via eBPF. Emits OTLP traces + Prometheus metrics.

## Prerequisites

- Linux kernel **5.8+** with BTF enabled (`ls /sys/kernel/btf/vmlinux` must exist)
- Root or `CAP_SYS_ADMIN` (or `privileged: true` in Kubernetes + `hostPID: true`)
- x86_64 or ARM64
- An OTLP receiver (Tempo, Alloy, OTel Collector) reachable from Beyla

## Common Workflows

### 1. Instrument a single binary with Docker

```bash
# 1. Run Beyla against the app's port (the app must already be running, listening on 8080)
docker run --privileged --pid=host \
  -v /sys/kernel/debug:/sys/kernel/debug:ro \
  -e BEYLA_OPEN_PORT=8080 \
  -e BEYLA_PROMETHEUS_PORT=8999 \
  -e OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4318 \
  -p 8999:8999 \
  grafana/beyla

# 2. Generate some traffic
curl http://localhost:8080/ ; curl http://localhost:8080/api/users/42

# 3. Verify Beyla emitted metrics — should list http_server_request_duration_seconds + counters
curl -s http://localhost:8999/metrics | grep -E '^http_(server|client)_request_duration'

# 4. Verify traces — in Grafana Explore on Tempo, search by service.name (default = process name)
#    Or: query Tempo's search API for spans with service.name="<app>"
```

### 2. Deploy as a cluster-wide DaemonSet

Full DaemonSet + RBAC YAML lives in [`references/kubernetes.md`](references/kubernetes.md). After applying:

```bash
# 1. Verify DaemonSet rollout
kubectl -n monitoring rollout status ds/beyla

# 2. Verify pods are Running, one per node
kubectl -n monitoring get pods -l app=beyla -o wide

# 3. Verify eBPF probes attached (no errors mentioning BTF or "permission denied")
kubectl -n monitoring logs ds/beyla --tail=50 | grep -Ei 'error|fail|btf' || echo "clean"

# 4. Verify telemetry is flowing — check the Tempo/Alloy receiver for spans from the cluster
#    Or scrape one pod directly:
kubectl -n monitoring port-forward ds/beyla 8999:8999 &
curl -s localhost:8999/metrics | head
```

### 3. Send to Grafana Cloud via Alloy

```yaml
# beyla-config.yml
otel_traces_export:  { endpoint: http://alloy:4318 }
otel_metrics_export: { endpoint: http://alloy:4318 }
```

```bash
# Verify Alloy is forwarding — check Alloy UI (localhost:12345) for the
# otelcol.receiver.otlp.beyla component showing received spans/metrics > 0.
```

Full Alloy + Beyla YAML: [`references/config.md`](references/config.md).

## Troubleshooting

- `failed to load BPF object` → kernel < 5.8 or BTF missing; check `/sys/kernel/btf/vmlinux`
- No spans in Tempo, but Prometheus metrics show → check `OTEL_EXPORTER_OTLP_ENDPOINT`, protocol (http vs grpc), and ports (4318 http / 4317 grpc)
- HTTP route cardinality explosion → set `routes.unmatched: heuristic` and add patterns (see [`references/config.md`](references/config.md))
- Pod restarts with `CrashLoopBackOff` → likely missing `hostPID: true` or `privileged: true` / required capabilities

## Resources

- [Beyla docs](https://grafana.com/docs/beyla/latest/)
- [Beyla GitHub](https://github.com/grafana/beyla)
- [`references/config.md`](references/config.md) — full config, env vars, samplers, routes decorator, generated metrics table, runtime matrix
- [`references/kubernetes.md`](references/kubernetes.md) — DaemonSet + RBAC + discovery filters + Helm
