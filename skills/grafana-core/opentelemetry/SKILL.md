---
name: opentelemetry
license: Apache-2.0
description: >
  OpenTelemetry with Grafana stack. Covers OTel SDK instrumentation for Go/Java/Python/Node.js/.NET,
  OTLP protocol and endpoint configuration, sending telemetry to Grafana Cloud via OTLP endpoint,
  Grafana Alloy as OTel collector, sampling strategies, Kubernetes OTel Operator, and migration
  from other observability tools. Use when instrumenting apps with OTel, configuring OTLP endpoints,
  setting up collectors, or migrating to OpenTelemetry.
---

# OpenTelemetry with Grafana

## Overview

OpenTelemetry (OTel) is a vendor-neutral framework for collecting observability data (metrics, logs,
traces, profiles). Grafana Labs integrates it as a core strategy, offering a full stack to collect,
ingest, store, analyze, and visualize telemetry data.

### Four-Step Implementation Model

1. **Instrument** - Add telemetry using Grafana SDKs, Beyla (eBPF), or upstream OTel SDKs
2. **Pipeline** - Build processing infrastructure with Grafana Alloy or OTel Collector
3. **Ingest** - Route data to Grafana Cloud OTLP endpoint or self-managed backends
4. **Analyze** - Dashboards, alerts, Application Observability, Drilldown apps

### Grafana Backends

| Signal | Backend |
|--------|---------|
| Metrics | Grafana Mimir |
| Logs | Grafana Loki |
| Traces | Grafana Tempo |
| Profiles | Grafana Pyroscope |

---

## OTLP Endpoint and Authentication

### Grafana Cloud OTLP Endpoint

Grafana Cloud exposes a managed OTLP gateway endpoint:

```
https://otlp-gateway-<region>.grafana.net/otlp
```

Example regions: `prod-us-east-0`, `prod-eu-west-0`, `prod-ap-southeast-0`

Full example:
```
https://otlp-gateway-prod-us-east-0.grafana.net/otlp
```

### Authentication - Basic Auth

Grafana Cloud OTLP uses **HTTP Basic Auth**:
- **Username**: Grafana Cloud Instance ID (numeric, e.g. `123456`)
- **Password**: Grafana Cloud API token (with MetricsPublisher, LogsPublisher, TracesPublisher roles)

#### Via environment variable (recommended)

```bash
# Base64-encode "instanceID:apiToken"
export OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic $(echo -n '123456:glc_eyJ...' | base64)"
```

#### Via Alloy environment variables

```bash
export GRAFANA_CLOUD_INSTANCE_ID=123456
export GRAFANA_CLOUD_API_KEY=glc_eyJ...
export GRAFANA_CLOUD_OTLP_ENDPOINT=https://otlp-gateway-prod-us-east-0.grafana.net/otlp
```

### Direct Send (no collector) - Environment Variables

```bash
export OTEL_EXPORTER_OTLP_ENDPOINT=https://otlp-gateway-prod-us-east-0.grafana.net/otlp
export OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
export OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic <base64(instanceID:apiToken)>"
export OTEL_RESOURCE_ATTRIBUTES="service.name=myapp,service.namespace=myteam,deployment.environment=production"
```

---

## Instrumentation by Language

### Go

**Requirements:** Go 1.22+

**Install packages:**
```bash
go get "go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp" \
  "go.opentelemetry.io/contrib/instrumentation/runtime" \
  "go.opentelemetry.io/otel" \
  "go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetrichttp" \
  "go.opentelemetry.io/otel/exporters/otlp/otlptrace" \
  "go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp" \
  "go.opentelemetry.io/otel/sdk" \
  "go.opentelemetry.io/otel/sdk/metric"
```

**Run with environment variables:**
```bash
OTEL_RESOURCE_ATTRIBUTES="service.name=myapp,service.namespace=myteam,deployment.environment=prod" \
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317 \
OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic <base64>" \
go run .
```

See `references/instrumentation.md` for full Go code example.

---

### Java (Grafana Distribution - JVM Agent)

**Requirements:** JDK 8+

**Download:** `grafana-opentelemetry-java.jar` from https://github.com/grafana/grafana-opentelemetry-java/releases

**Run:**
```bash
OTEL_RESOURCE_ATTRIBUTES="service.name=shoppingcart,service.namespace=ecommerce,deployment.environment=production" \
OTEL_EXPORTER_OTLP_ENDPOINT=https://otlp-gateway-prod-us-east-0.grafana.net/otlp \
OTEL_EXPORTER_OTLP_PROTOCOL="http/protobuf" \
OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic <base64>" \
java -javaagent:/path/to/grafana-opentelemetry-java.jar -jar myapp.jar
```

**Optional: Data saver mode** (reduces metric cardinality):
```bash
export GRAFANA_OTEL_APPLICATION_OBSERVABILITY_METRICS=true
```

**Debug:**
```bash
export OTEL_JAVAAGENT_DEBUG=true
# Enable console output alongside OTLP
export OTEL_TRACES_EXPORTER=otlp,console
export OTEL_METRICS_EXPORTER=otlp,console
export OTEL_LOGS_EXPORTER=otlp,console
```

---

### Node.js

**Install:**
```bash
npm install --save @opentelemetry/api
npm install --save @opentelemetry/auto-instrumentations-node
```

**Run:**
```bash
OTEL_TRACES_EXPORTER="otlp" \
OTEL_METRICS_EXPORTER="otlp" \
OTEL_LOGS_EXPORTER="otlp" \
OTEL_NODE_RESOURCE_DETECTORS="env,host,os" \
OTEL_RESOURCE_ATTRIBUTES="service.name=myapp,service.namespace=myteam,deployment.environment=prod" \
OTEL_EXPORTER_OTLP_ENDPOINT=https://otlp-gateway-prod-us-east-0.grafana.net/otlp \
OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic <base64>" \
NODE_OPTIONS="--require @opentelemetry/auto-instrumentations-node/register" \
node app.js
```

**Warning:** Bundlers like `@vercel/ncc` can break auto-instrumentation hooks.

See `references/instrumentation.md` for manual SDK setup example.

---

### Python

**Install:**
```bash
pip install "opentelemetry-distro[otlp]"
opentelemetry-bootstrap -a install
```

**Run:**
```bash
OTEL_RESOURCE_ATTRIBUTES="service.name=myapp,service.namespace=myteam,deployment.environment=prod" \
OTEL_EXPORTER_OTLP_ENDPOINT=https://otlp-gateway-prod-us-east-0.grafana.net/otlp \
OTEL_EXPORTER_OTLP_PROTOCOL="http/protobuf" \
OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic <base64>" \
opentelemetry-instrument python app.py
```

**Multi-process servers** (Gunicorn, uWSGI): implement post-fork hooks to reinitialize OTel providers per worker.

---

### .NET (Grafana Distribution)

**Install NuGet:**
```bash
dotnet add package Grafana.OpenTelemetry
```

**ASP.NET Core setup:**
```csharp
using Grafana.OpenTelemetry;

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddOpenTelemetry()
    .WithTracing(configure => configure.UseGrafana())
    .WithMetrics(configure => configure.UseGrafana());
builder.Logging.AddOpenTelemetry(options => options.UseGrafana());
```

**Run:**
```bash
OTEL_RESOURCE_ATTRIBUTES="service.name=myapp,service.namespace=myteam,deployment.environment=prod" \
OTEL_EXPORTER_OTLP_ENDPOINT=https://otlp-gateway-prod-us-east-0.grafana.net/otlp \
OTEL_EXPORTER_OTLP_PROTOCOL="http/protobuf" \
OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic <base64>" \
dotnet run
```

**Requirements:** .NET 6+ or .NET Framework 4.6.2+

See `references/instrumentation.md` for full .NET examples.

---

### Beyla (eBPF - Language Agnostic)

Grafana Beyla instruments at the network layer - no code changes required, works with any language.

```bash
# Docker
docker run --rm -it \
  --privileged \
  -e BEYLA_SERVICE_NAME=myapp \
  -e OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317 \
  -v /sys/kernel/security:/sys/kernel/security \
  grafana/beyla
```

Verify with: `curl http://localhost:9090/metrics`

Full docs: https://grafana.com/docs/beyla/

---

## Grafana Alloy Collector

Grafana Alloy is the recommended OTel Collector distribution. It combines upstream OTel Collector
components with Prometheus exporters for infrastructure + application observability correlation.

### Why Use a Collector?

- **Cost control**: Aggregate, sample, and drop data before sending
- **Reliability**: Buffer and retry on connection failures
- **Enrichment**: Add resource attributes, transform, redact, and route data

### Alloy Ports

| Port | Protocol | Purpose |
|------|----------|---------|
| 4317 | gRPC | OTLP gRPC receiver |
| 4318 | HTTP | OTLP HTTP/protobuf receiver |

### Application -> Alloy -> Grafana Cloud

**Application env vars** (point to local Alloy):
```bash
export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317
export OTEL_EXPORTER_OTLP_PROTOCOL=grpc
```

**Alloy config env vars** (Alloy -> Grafana Cloud):
```bash
export GRAFANA_CLOUD_OTLP_ENDPOINT=https://otlp-gateway-prod-us-east-0.grafana.net/otlp
export GRAFANA_CLOUD_INSTANCE_ID=123456
export GRAFANA_CLOUD_API_KEY=glc_eyJ...
```

See `references/collector-config.md` for full Alloy configuration.

---

## Kubernetes Setup

### Option 1: Grafana Kubernetes Monitoring Helm Chart (recommended)

The Grafana Kubernetes Monitoring Helm chart deploys Alloy with OTLP receivers pre-configured.

1. Enable "OTLP Receivers" in the Cluster Configuration tab
2. Get gRPC/HTTP endpoints from "Configure Application Instrumentation" section
3. Point apps to the in-cluster Alloy endpoint:

```bash
export OTEL_EXPORTER_OTLP_ENDPOINT=<GRPC_ENDPOINT_FROM_HELM>
export OTEL_EXPORTER_OTLP_PROTOCOL=grpc
```

### Option 2: OpenTelemetry Operator

Install via official docs, then use `Instrumentation` CR for auto-injection:

```yaml
apiVersion: opentelemetry.io/v1alpha1
kind: Instrumentation
metadata:
  name: my-instrumentation
spec:
  exporter:
    endpoint: http://otelcol:4317
  propagators:
    - tracecontext
    - baggage
  java:
    # Use Grafana distribution image
    image: us-docker.pkg.dev/grafanalabs-global/docker-grafana-opentelemetry-java-prod/grafana-opentelemetry-java:2.3.0-beta.1
  nodejs: {}
  python: {}
```

**Inject into pods** with annotation:
```yaml
metadata:
  annotations:
    instrumentation.opentelemetry.io/inject-java: "true"
    # or: inject-nodejs, inject-python, inject-dotnet
```

See `references/collector-config.md` for Kubernetes Alloy Helm values and OTel Collector YAML.

---

## Sampling Strategies

### Head-Based Sampling

Decision made at trace start - low overhead, may miss rare errors.

**Environment variable (probability sampler):**
```bash
export OTEL_TRACES_SAMPLER=parentbased_traceidratio
export OTEL_TRACES_SAMPLER_ARG=0.1   # 10% of traces
```

**Alloy head sampling config:**
```alloy
otelcol.processor.probabilistic_sampler "default" {
  sampling_percentage = 10
  output {
    traces = [otelcol.exporter.otlphttp.grafana_cloud.input]
  }
}
```

### Tail-Based Sampling

Decision made after all spans collected - can sample based on outcome (e.g. keep all errors).

**Alloy tail sampling config:**
```alloy
otelcol.processor.tail_sampling "default" {
  decision_wait            = "10s"
  num_traces               = 100000
  expected_new_traces_per_sec = 10

  policy {
    name = "keep-errors"
    type = "status_code"
    status_code {
      status_codes = ["ERROR"]
    }
  }

  policy {
    name = "probabilistic-sample"
    type = "probabilistic"
    probabilistic {
      sampling_percentage = 10
    }
  }

  output {
    traces = [otelcol.exporter.otlphttp.grafana_cloud.input]
  }
}
```

---

## Key Environment Variables Reference

| Variable | Description | Example |
|----------|-------------|---------|
| `OTEL_EXPORTER_OTLP_ENDPOINT` | OTLP receiver URL | `https://otlp-gateway-prod-us-east-0.grafana.net/otlp` |
| `OTEL_EXPORTER_OTLP_PROTOCOL` | Transport protocol | `grpc` or `http/protobuf` |
| `OTEL_EXPORTER_OTLP_HEADERS` | Auth headers | `Authorization=Basic <base64>` |
| `OTEL_RESOURCE_ATTRIBUTES` | Service metadata | `service.name=myapp,service.namespace=team,deployment.environment=prod` |
| `OTEL_TRACES_EXPORTER` | Trace exporter type | `otlp` |
| `OTEL_METRICS_EXPORTER` | Metrics exporter type | `otlp` |
| `OTEL_LOGS_EXPORTER` | Logs exporter type | `otlp` |
| `OTEL_SERVICE_NAME` | Service name (shorthand) | `myapp` |
| `OTEL_TRACES_SAMPLER` | Sampler type | `parentbased_traceidratio` |
| `OTEL_TRACES_SAMPLER_ARG` | Sampler argument | `0.1` (10%) |

### Key Resource Attributes

| Attribute | Purpose | Example |
|-----------|---------|---------|
| `service.name` | Service identifier | `shoppingcart` |
| `service.namespace` | Groups related services | `ecommerce` |
| `deployment.environment` | Environment tier | `production`, `staging` |
| `service.version` | App version | `1.2.3` |

---

## Useful Links

- Grafana OTel docs: https://grafana.com/docs/opentelemetry/
- Grafana Cloud OTLP: https://grafana.com/docs/grafana-cloud/send-data/otlp/
- Grafana Java Agent: https://github.com/grafana/grafana-opentelemetry-java
- Grafana .NET SDK: https://github.com/grafana/grafana-opentelemetry-dotnet
- Grafana Alloy: https://grafana.com/docs/alloy/
- Grafana Beyla: https://grafana.com/docs/beyla/
- OTel Collector: https://opentelemetry.io/docs/collector/
- OTel Operator: https://opentelemetry.io/docs/kubernetes/operator/
