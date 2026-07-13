# Alloy eBPF pipeline + ProfileQL

## Alloy eBPF auto-instrumentation

No code changes. Supports: C/C++, Go, Rust, Java (Hotspot), Python, Ruby, Node.js, PHP, .NET, V8.

Requirements: Alloy as root, host PID namespace, Linux 5.8+ with BTF (or RHEL 4.18+).

```alloy
discovery.kubernetes "all_pods" {
  role = "pod"
  selectors { field = "spec.nodeName=" + sys.env("HOSTNAME") }
}

discovery.relabel "local_pods" {
  targets = discovery.kubernetes.all_pods.targets
  rule {
    source_labels = ["__meta_kubernetes_namespace"]
    target_label  = "namespace"
  }
}

pyroscope.ebpf "local_pods" {
  forward_to        = [pyroscope.write.cloud.receiver]
  targets           = discovery.relabel.local_pods.output
  sample_rate       = 97          // samples per second
  collect_interval  = "15s"
}

pyroscope.write "cloud" {
  endpoint {
    url = "https://profiles-prod-xxx.grafana.net"
    basic_auth {
      username = sys.env("PYROSCOPE_USER")
      password = sys.env("GRAFANA_API_KEY")
    }
  }
}
```

## ProfileQL

```
# All CPU profiles for a service
{service_name="myapp", __profile_type__="process_cpu:cpu:nanoseconds:cpu:nanoseconds"}

# Filter by label
{service_name="myapp", env="prod"}
```

Profile type format: `<type>:<value_type>:<value_unit>:<span_name>:<span_unit>`.

Common types:

- `process_cpu:cpu:nanoseconds:cpu:nanoseconds` — CPU time
- `memory:inuse_space:bytes:space:bytes` — Heap in-use
- `memory:alloc_space:bytes:space:bytes` — Heap allocations
- `goroutine:goroutine:count::` — Goroutine count (Go)
- `mutex:contentions:count::` — Mutex contentions

## Server `/ready` endpoint

The Pyroscope server exposes `/ready` (HTTP 200) and a `/api/v1/labels` endpoint for verification.
