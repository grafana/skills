---
name: opentelemetry
license: Apache-2.0
description: Instrument any app with OpenTelemetry and ship metrics / logs / traces to Grafana Cloud or self-hosted Mimir / Loki / Tempo / Pyroscope. Covers SDK auto-instrumentation for Go, Java (Grafana JVM agent), Python (`opentelemetry-instrument`), Node.js, .NET (`Grafana.OpenTelemetry`), Beyla eBPF for zero-code; Grafana Cloud OTLP gateway + Basic-auth (instanceID + API key, base64); env-var config (`OTEL_EXPORTER_OTLP_*`, `OTEL_RESOURCE_ATTRIBUTES`); Alloy / OTel-Collector pipelines; Kubernetes Operator inject-annotations; and head + tail sampling. Use when instrumenting a service, pointing OTLP at Grafana Cloud, switching from Jaeger / Datadog / New Relic, choosing head- vs tail-sampling, or debugging "spans aren't showing in Explore" — even when the user says "auto-instrument my Java app", "send traces to Grafana", "what env vars do I set", "OTLP endpoint", or "Operator inject" without naming OpenTelemetry.
---

# OpenTelemetry with Grafana

> **Docs**: https://grafana.com/docs/opentelemetry/

Vendor-neutral instrumentation pipeline. Apps speak OTLP → Alloy (or direct) → Grafana Cloud (Mimir / Loki / Tempo / Pyroscope).

## Backends

| Signal | Backend |
|--------|---------|
| Metrics | Grafana Mimir |
| Logs | Grafana Loki |
| Traces | Grafana Tempo |
| Profiles | Grafana Pyroscope |

## Prerequisites

- Grafana Cloud stack OR self-hosted Mimir / Loki / Tempo
- Cloud OTLP endpoint: `https://otlp-gateway-<region>.grafana.net/otlp`
- Basic-auth credentials: numeric instance ID + API token with `MetricsPublisher` + `LogsPublisher` + `TracesPublisher`
- An app to instrument

## Common Workflows

### 1. Authenticate to the Grafana Cloud OTLP endpoint

```bash
# 1. Build the auth header
INSTANCE_ID=123456
API_KEY="glc_eyJ..."
export OTEL_EXPORTER_OTLP_ENDPOINT=https://otlp-gateway-prod-us-east-0.grafana.net/otlp
export OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
export OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic $(echo -n "${INSTANCE_ID}:${API_KEY}" | base64)"
export OTEL_RESOURCE_ATTRIBUTES="service.name=myapp,service.namespace=myteam,deployment.environment=prod"

# 2. Smoke-test creds with a curl POST against the OTLP traces endpoint (empty body)
curl -s -o /dev/null -w "%{http_code}\n" \
  -X POST -H "Content-Type: application/x-protobuf" \
  -H "Authorization: Basic $(echo -n "${INSTANCE_ID}:${API_KEY}" | base64)" \
  "$OTEL_EXPORTER_OTLP_ENDPOINT/v1/traces" --data-binary '\n'
# Expect 400 (malformed payload) — NOT 401 (auth) or 404 (wrong endpoint).
```

### 2. Auto-instrument a Java app + verify

```bash
# 1. Download the Grafana JVM agent (single jar)
curl -sLO https://github.com/grafana/grafana-opentelemetry-java/releases/latest/download/grafana-opentelemetry-java.jar

# 2. Run with the agent + env from step 1
java -javaagent:./grafana-opentelemetry-java.jar -jar myapp.jar

# 3. Generate traffic, then verify in Grafana → Explore → Tempo:
#    TraceQL: { resource.service.name = "myapp" }
#    Expect spans within ~30s. Also verify metrics:
#    PromQL: count by (service_name)({service_name="myapp"})
```

### 3. Auto-instrument a Python app

```bash
pip install "opentelemetry-distro[otlp]"
opentelemetry-bootstrap -a install

# Same env vars as step 1, then:
opentelemetry-instrument python app.py

# Verify the same way — Explore → Traces filter service.name=myapp.
```

### 4. Add Alloy as a buffering / sampling collector

```bash
# Application points at local Alloy (gRPC fastest)
export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317
export OTEL_EXPORTER_OTLP_PROTOCOL=grpc

# Alloy environment for forwarding to Cloud
export GRAFANA_CLOUD_OTLP_ENDPOINT=https://otlp-gateway-prod-us-east-0.grafana.net/otlp
export GRAFANA_CLOUD_INSTANCE_ID=$INSTANCE_ID
export GRAFANA_CLOUD_API_KEY=$API_KEY
alloy run /etc/alloy/config.alloy

# Verify Alloy received and forwarded
curl -s http://localhost:12345/metrics | grep otelcol_exporter_sent_spans
```

Full Alloy config + tail-sampling block + OTel Collector YAML + K8s Operator install: [`references/collector-config.md`](references/collector-config.md).

SDK-by-language details (Go full code, Node manual setup, .NET ASP.NET Core, all the env-var quirks): [`references/instrumentation.md`](references/instrumentation.md).

### 5. Kubernetes — auto-inject via the Operator

```yaml
apiVersion: opentelemetry.io/v1alpha1
kind: Instrumentation
metadata: { name: my-instrumentation }
spec:
  exporter: { endpoint: http://otelcol:4317 }
  propagators: [tracecontext, baggage]
  java:
    image: us-docker.pkg.dev/grafanalabs-global/docker-grafana-opentelemetry-java-prod/grafana-opentelemetry-java:2.3.0-beta.1
  nodejs: {}
  python: {}
```

Then annotate pods:

```yaml
metadata:
  annotations:
    instrumentation.opentelemetry.io/inject-java: "true"
    # or: inject-nodejs, inject-python, inject-dotnet
```

```bash
# Verify the operator injected the agent
kubectl describe pod <pod> | grep -A2 'opentelemetry-auto-instrumentation'
# Then run the same Grafana Explore checks.
```

## Sampling — when to pick which

```bash
# Head sampling (cheap, decided at start; may lose rare errors)
export OTEL_TRACES_SAMPLER=parentbased_traceidratio
export OTEL_TRACES_SAMPLER_ARG=0.1   # 10%
```

Tail sampling (decides after seeing the whole trace — keep errors + sample the rest) requires an Alloy / OTel-Collector `tail_sampling` processor; full block in [`references/collector-config.md`](references/collector-config.md).

## Key environment variables

| Variable | Example |
|----------|---------|
| `OTEL_EXPORTER_OTLP_ENDPOINT` | `https://otlp-gateway-prod-us-east-0.grafana.net/otlp` |
| `OTEL_EXPORTER_OTLP_PROTOCOL` | `grpc` or `http/protobuf` |
| `OTEL_EXPORTER_OTLP_HEADERS` | `Authorization=Basic <base64>` |
| `OTEL_RESOURCE_ATTRIBUTES` | `service.name=app,service.namespace=team,deployment.environment=prod` |
| `OTEL_SERVICE_NAME` | shorthand for `service.name` |
| `OTEL_TRACES_SAMPLER` / `_ARG` | `parentbased_traceidratio` / `0.1` |

## Troubleshooting

- 401 from OTLP gateway → instance ID is not numeric, or API key missing publisher roles
- 404 → endpoint URL wrong (must end with `/otlp`)
- Spans missing → check `OTEL_EXPORTER_OTLP_PROTOCOL` matches transport (Cloud OTLP gateway = `http/protobuf`, Alloy local = `grpc`)
- Node.js auto-instrumentation broken after bundling → bundlers like `@vercel/ncc` defeat the require hooks
- Python under Gunicorn / uWSGI shows no spans → reinit OTel providers in a post-fork hook

## Resources

- [Grafana OTel docs](https://grafana.com/docs/opentelemetry/)
- [Grafana Cloud OTLP](https://grafana.com/docs/grafana-cloud/send-data/otlp/)
- [Grafana JVM agent](https://github.com/grafana/grafana-opentelemetry-java)
- [Grafana .NET SDK](https://github.com/grafana/grafana-opentelemetry-dotnet)
- [OTel Operator](https://opentelemetry.io/docs/kubernetes/operator/)
