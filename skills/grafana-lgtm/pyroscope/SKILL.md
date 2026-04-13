---
name: pyroscope
license: Apache-2.0
description: >
  Grafana Pyroscope continuous profiling platform. Covers instrumentation of Go/Java/Python/Ruby/Node.js/
  .NET/Rust apps via SDKs or eBPF (Alloy), flame graph analysis, ProfileQL queries, server configuration
  and architecture, Grafana Cloud Profiles integration, and trace-profile linking (Span Profiles).
  Use when working with profiling data, instrumenting apps for Pyroscope, analyzing performance profiles,
  or deploying Pyroscope server.
---

# Grafana Pyroscope - Continuous Profiling

> **Docs**: https://grafana.com/docs/pyroscope/latest/

Continuous profiling aggregation system — understand resource usage down to source code line numbers.

## Instrumentation Methods

Three ways to send profiles to Pyroscope:

1. **Grafana Alloy (preferred)**: eBPF auto-instrumentation, no code changes
2. **SDK**: Push profiles directly from your application
3. **SDK → Alloy**: SDK sends to Alloy's `pyroscope.receive_http`, Alloy forwards to Pyroscope

## SDK Examples

### Python

```bash
pip install pyroscope-io
```

```python
import pyroscope, os

pyroscope.configure(
    application_name = "my.python.app",
    server_address   = "http://pyroscope:4040",
    sample_rate      = 100,
    oncpu            = True,
    tags             = {"region": os.getenv("REGION"), "env": "prod"},
)

# Dynamic labels for specific code sections
with pyroscope.tag_wrapper({"controller": "slow_controller"}):
    slow_code()
```

**Grafana Cloud:**
```python
pyroscope.configure(
    application_name   = "my.python.app",
    server_address     = "https://profiles-prod-xxx.grafana.net",
    basic_auth_username = "123456",
    basic_auth_password = os.getenv("GRAFANA_API_KEY"),
)
```

### Java

```xml
<!-- Maven -->
<dependency>
  <groupId>io.pyroscope</groupId>
  <artifactId>agent</artifactId>
  <version>2.1.2</version>
</dependency>
```

```java
// Method 1: Application code
PyroscopeAgent.start(
    new Config.Builder()
        .setApplicationName("my-java-app")
        .setProfilingEvent(EventType.ITIMER)
        .setFormat(Format.JFR)           // required for multiple events
        .setServerAddress("http://pyroscope:4040")
        .build()
);

// Dynamic labels
Pyroscope.LabelsWrapper.run(new LabelsSet("controller", "slow_controller"), () -> {
    slowCode();
});
```

```bash
# Method 2: Java Agent (no code changes)
export PYROSCOPE_APPLICATION_NAME=my.java.app
export PYROSCOPE_SERVER_ADDRESS=http://pyroscope:4040
java -javaagent:pyroscope.jar -jar app.jar
```

**Key Java config:**

| Env Var | Description | Default |
|---------|-------------|---------|
| `PYROSCOPE_FORMAT` | `jfr` for multiple events | `collapsed` |
| `PYROSCOPE_PROFILER_EVENT` | `itimer`, `cpu`, `wall` | `itimer` |
| `PYROSCOPE_PROFILER_ALLOC` | Allocation bytes threshold; `0` = all | disabled |
| `PYROSCOPE_PROFILER_LOCK` | Lock contention threshold (ns) | disabled |
| `PYROSCOPE_UPLOAD_INTERVAL` | Upload frequency | `10s` |

### Node.js

```bash
npm install @pyroscope/nodejs
```

```javascript
const Pyroscope = require('@pyroscope/nodejs');

Pyroscope.init({
    serverAddress: 'http://pyroscope:4040',
    appName: 'my-node-service',
    tags: { region: process.env.REGION },
    basicAuthUser: process.env.PYROSCOPE_USER,
    basicAuthPassword: process.env.PYROSCOPE_PASSWORD,
    flushIntervalMs: 60000,
});
Pyroscope.start();

// Dynamic labels
Pyroscope.wrapWithLabels({ vehicle: 'bike' }, () => slowCode());
```

### Ruby

```bash
bundle add pyroscope
```

```ruby
require 'pyroscope'

Pyroscope.configure do |config|
  config.application_name = "my.ruby.app"
  config.server_address   = "http://pyroscope:4040"
  config.tags = { hostname: ENV["HOSTNAME"] }
end

# Dynamic tags
Pyroscope.tag_wrapper({ controller: "slow_controller" }) do
  slow_code
end
```

### .NET

```bash
# System requirements: Linux amd64, .NET 6+
export PYROSCOPE_APPLICATION_NAME=my.dotnet.app
export PYROSCOPE_SERVER_ADDRESS=http://pyroscope:4040
export PYROSCOPE_PROFILING_ENABLED=1
export CORECLR_ENABLE_PROFILING=1
export CORECLR_PROFILER={BD1A650D-AC5D-4896-B64F-D6FA25D6B26A}
export CORECLR_PROFILER_PATH=/dotnet/Pyroscope.Profiler.Native.so
export LD_PRELOAD=/dotnet/Pyroscope.Linux.ApiWrapper.x64.so
```

```csharp
// Dynamic labels
var labels = Pyroscope.LabelSet.Empty.BuildUpon()
    .Add("controller", "slow")
    .Build();
Pyroscope.LabelsWrapper.Do(labels, () => SlowCode());
```

### Rust

```bash
cargo add pyroscope pyroscope_pprofrs
```

```rust
let pprof_config = PprofConfig::new().sample_rate(100);
let agent = PyroscopeAgent::builder("http://pyroscope:4040", "my-rust-app")
    .backend(pprof_backend(pprof_config))
    .tags([("env", "prod"), ("region", "us-east")].to_vec())
    .basic_auth(user, password)
    .build()?;
let agent_running = agent.start().unwrap();
// ... app runs ...
let agent_ready = agent_running.stop().unwrap();
agent_ready.shutdown();
```

## eBPF Auto-Instrumentation via Alloy

No code changes needed. Supports: C/C++, Go, Rust, Java (Hotspot JVM), Python, Ruby, Node.js, PHP, .NET, V8.

```alloy
discovery.kubernetes "all_pods" {
  role = "pod"
  selectors {
    field = "spec.nodeName=" + sys.env("HOSTNAME")
  }
}

discovery.relabel "local_pods" {
  targets = discovery.kubernetes.all_pods.targets
  rule {
    source_labels = ["__meta_kubernetes_namespace"]
    target_label  = "namespace"
  }
}

pyroscope.ebpf "local_pods" {
  forward_to     = [pyroscope.write.cloud.receiver]
  targets        = discovery.relabel.local_pods.output
  sample_rate    = 97          // samples per second
  collect_interval = "15s"
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

Requirements for eBPF:
- Run Alloy as root, in host PID namespace
- Linux 5.8+ with BTF enabled (or RHEL 4.18+)

## ProfileQL Queries

```
# All CPU profiles for a service
{service_name="myapp", __profile_type__="process_cpu:cpu:nanoseconds:cpu:nanoseconds"}

# Filter by label
{service_name="myapp", env="prod"}

# Profile types format: <type>:<value_type>:<value_unit>:<span_name>:<span_unit>
```

**Common profile types:**
- `process_cpu:cpu:nanoseconds:cpu:nanoseconds` - CPU time
- `memory:inuse_space:bytes:space:bytes` - Heap in use
- `memory:alloc_space:bytes:space:bytes` - Heap allocations
- `goroutine:goroutine:count::` - Goroutine count (Go)
- `mutex:contentions:count::` - Mutex contentions

## Profile Types by Language

| Language | CPU | Memory | Goroutines | Allocations |
|----------|-----|--------|------------|-------------|
| Go | ✓ | ✓ | ✓ | ✓ |
| Java | ✓ | ✓ | ✓ | ✓ |
| Python | ✓ | - | - | - |
| Node.js | ✓ | ✓ | - | ✓ |
| Ruby | ✓ | ✓ | - | - |
| .NET | ✓ | ✓ | - | ✓ |
| Rust | ✓ | - | - | - |
| eBPF | ✓ | - | - | - |

## Tag Rules

Valid tags: `[a-zA-Z_][a-zA-Z0-9_]*` — periods NOT allowed.

## References

- [SDKs Reference](references/sdks.md)
- [ProfileQL](references/profileql.md)
- [Server Config](references/server-config.md)
