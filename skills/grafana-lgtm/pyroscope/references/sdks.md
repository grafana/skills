# Pyroscope SDKs by language

Each SDK pushes profiles to `server_address`. For Grafana Cloud Profiles, use the basic-auth form with the Pyroscope user (numeric stack id) + a Grafana Cloud API key.

## Python

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
with pyroscope.tag_wrapper({"controller": "slow_controller"}):
    slow_code()
```

Grafana Cloud:

```python
pyroscope.configure(
    application_name="my.python.app",
    server_address="https://profiles-prod-xxx.grafana.net",
    basic_auth_username="123456",
    basic_auth_password=os.getenv("GRAFANA_API_KEY"),
)
```

## Java

```xml
<!-- Maven -->
<dependency>
  <groupId>io.pyroscope</groupId>
  <artifactId>agent</artifactId>
  <version>2.1.2</version>
</dependency>
```

```java
PyroscopeAgent.start(
    new Config.Builder()
        .setApplicationName("my-java-app")
        .setProfilingEvent(EventType.ITIMER)
        .setFormat(Format.JFR)
        .setServerAddress("http://pyroscope:4040")
        .build()
);

Pyroscope.LabelsWrapper.run(new LabelsSet("controller", "slow_controller"), () -> {
    slowCode();
});
```

Or Java agent (no code change):

```bash
export PYROSCOPE_APPLICATION_NAME=my.java.app
export PYROSCOPE_SERVER_ADDRESS=http://pyroscope:4040
java -javaagent:pyroscope.jar -jar app.jar
```

| Env var | Description | Default |
|---------|-------------|---------|
| `PYROSCOPE_FORMAT` | `jfr` for multiple events | `collapsed` |
| `PYROSCOPE_PROFILER_EVENT` | `itimer`, `cpu`, `wall` | `itimer` |
| `PYROSCOPE_PROFILER_ALLOC` | Allocation bytes threshold; `0` = all | disabled |
| `PYROSCOPE_PROFILER_LOCK` | Lock contention threshold (ns) | disabled |
| `PYROSCOPE_UPLOAD_INTERVAL` | Upload frequency | `10s` |

## Node.js

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
Pyroscope.wrapWithLabels({ vehicle: 'bike' }, () => slowCode());
```

## Ruby

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
Pyroscope.tag_wrapper({ controller: "slow_controller" }) { slow_code }
```

## .NET (Linux amd64, .NET 6+)

```bash
export PYROSCOPE_APPLICATION_NAME=my.dotnet.app
export PYROSCOPE_SERVER_ADDRESS=http://pyroscope:4040
export PYROSCOPE_PROFILING_ENABLED=1
export CORECLR_ENABLE_PROFILING=1
export CORECLR_PROFILER={BD1A650D-AC5D-4896-B64F-D6FA25D6B26A}
export CORECLR_PROFILER_PATH=/dotnet/Pyroscope.Profiler.Native.so
export LD_PRELOAD=/dotnet/Pyroscope.Linux.ApiWrapper.x64.so
```

```csharp
var labels = Pyroscope.LabelSet.Empty.BuildUpon().Add("controller", "slow").Build();
Pyroscope.LabelsWrapper.Do(labels, () => SlowCode());
```

## Rust

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
let running = agent.start().unwrap();
// ...
let ready = running.stop().unwrap();
ready.shutdown();
```

## Profile types by language

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

Valid tag chars: `[a-zA-Z_][a-zA-Z0-9_]*` — periods NOT allowed.
