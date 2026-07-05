# Grafana Cloud Application Observability - APM Setup Reference

## Overview

Application Observability is Grafana Cloud's pre-built APM (Application Performance Monitoring) product. It requires:

1. Applications instrumented with OpenTelemetry (OTel)
2. Traces sent to Grafana Cloud (via Alloy or direct OTLP)
3. Span metrics generated from those traces (auto-configured in Grafana Cloud)

Docs: https://grafana.com/docs/grafana-cloud/monitor-applications/application-observability/

## Architecture

```
Your Application
    |
    | OTel SDK (OTLP gRPC/HTTP)
    v
Grafana Alloy (local collector)  OR  direct to Grafana Cloud
    |
    |-- Traces --> Grafana Tempo --> Span Metrics Generator
    |                                        |
    |                                        v
    |-- Metrics ----------------------> Grafana Mimir
    |
    |-- Logs ----> Grafana Loki
    |
    v
Application Observability UI (Service Inventory, Service Map, etc.)
```

## Step 1: Instrument Your Application with OTel

### Required Resource Attributes

These MUST be set for Application Observability to function correctly:

```bash
# Minimum required
OTEL_SERVICE_NAME=my-api

# Strongly recommended
OTEL_RESOURCE_ATTRIBUTES=service.namespace=my-team,deployment.environment=production,service.version=1.2.3
```

How Grafana uses these:
- `service.name` -> `service_name` label, used throughout UI
- `service.namespace` + `service.name` -> `job` label (`namespace/service.name`)
- `deployment.environment` -> `deployment_environment` label, used for environment filtering
- `service.version` -> shown in Service Overview; used for release comparison

Additional attributes for enriched UI:
```bash
OTEL_RESOURCE_ATTRIBUTES=\
  service.namespace=payments,\
  deployment.environment=production,\
  service.version=2.3.1,\
  k8s.cluster.name=prod-us-east,\
  k8s.namespace.name=payments-ns,\
  cloud.region=us-east-1,\
  host.name=payments-worker-1
```

### Node.js Example

```bash
npm install @opentelemetry/sdk-node \
            @opentelemetry/auto-instrumentations-node \
            @opentelemetry/exporter-trace-otlp-grpc
```

```javascript
// tracing.js - load BEFORE your app
const { NodeSDK } = require('@opentelemetry/sdk-node');
const { getNodeAutoInstrumentations } = require('@opentelemetry/auto-instrumentations-node');
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-grpc');
const { Resource } = require('@opentelemetry/resources');
const { SEMRESATTRS_SERVICE_NAME, SEMRESATTRS_SERVICE_NAMESPACE } = require('@opentelemetry/semantic-conventions');

const sdk = new NodeSDK({
  resource: new Resource({
    [SEMRESATTRS_SERVICE_NAME]: 'my-node-api',
    [SEMRESATTRS_SERVICE_NAMESPACE]: 'my-team',
    'deployment.environment': 'production',
    'service.version': '1.2.0',
  }),
  traceExporter: new OTLPTraceExporter({
    url: 'http://localhost:4317', // Alloy or direct
  }),
  instrumentations: [getNodeAutoInstrumentations()],
});

sdk.start();
```

Run with:
```bash
node -r ./tracing.js app.js
```

### Python Example

```bash
pip install opentelemetry-distro opentelemetry-exporter-otlp
opentelemetry-bootstrap -a install
```

```python
# Manual setup (alternatively use opentelemetry-instrument CLI)
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.resources import Resource

resource = Resource.create({
    "service.name": "my-python-api",
    "service.namespace": "my-team",
    "deployment.environment": "production",
    "service.version": "1.0.0",
})

provider = TracerProvider(resource=resource)
exporter = OTLPSpanExporter(endpoint="http://localhost:4317", insecure=True)
provider.add_span_processor(BatchSpanProcessor(exporter))
trace.set_tracer_provider(provider)
```

Or using the auto-instrumentation CLI:
```bash
OTEL_SERVICE_NAME=my-python-api \
OTEL_RESOURCE_ATTRIBUTES="service.namespace=my-team,deployment.environment=production" \
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317 \
opentelemetry-instrument python app.py
```

### Java Example

Using the OTel Java agent (zero-code instrumentation):

```bash
wget https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/latest/download/opentelemetry-javaagent.jar

OTEL_SERVICE_NAME=my-java-api \
OTEL_RESOURCE_ATTRIBUTES="service.namespace=my-team,deployment.environment=production,service.version=1.0.0" \
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317 \
java -javaagent:opentelemetry-javaagent.jar -jar myapp.jar
```

Grafana also provides a custom Java distribution:
```bash
# Grafana's distribution with extra features
wget https://github.com/grafana/grafana-opentelemetry-java/releases/latest/download/grafana-opentelemetry-java.jar
```

### Go Example

```bash
go get go.opentelemetry.io/otel \
       go.opentelemetry.io/otel/sdk \
       go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc
```

```go
package main

import (
    "go.opentelemetry.io/otel"
    "go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
    "go.opentelemetry.io/otel/sdk/resource"
    sdktrace "go.opentelemetry.io/otel/sdk/trace"
    semconv "go.opentelemetry.io/otel/semconv/v1.21.0"
)

func initTracer() func() {
    ctx := context.Background()

    exporter, _ := otlptracegrpc.New(ctx,
        otlptracegrpc.WithEndpoint("localhost:4317"),
        otlptracegrpc.WithInsecure(),
    )

    res, _ := resource.New(ctx,
        resource.WithAttributes(
            semconv.ServiceName("my-go-api"),
            semconv.ServiceNamespace("my-team"),
            semconv.ServiceVersion("1.0.0"),
            attribute.String("deployment.environment", "production"),
        ),
    )

    tp := sdktrace.NewTracerProvider(
        sdktrace.WithBatcher(exporter),
        sdktrace.WithResource(res),
    )
    otel.SetTracerProvider(tp)

    return func() { tp.Shutdown(ctx) }
}
```

## Step 2: Install and Configure Grafana Alloy

Alloy is the recommended local OTel collector that forwards data to Grafana Cloud.

### Install Alloy

```bash
# macOS
brew install grafana/grafana/alloy

# Linux (Debian/Ubuntu)
sudo apt-get install alloy

# Docker
docker run --rm \
  -v ./config.alloy:/etc/alloy/config.alloy \
  -p 4317:4317 -p 4318:4318 \
  grafana/alloy:latest run /etc/alloy/config.alloy

# Kubernetes (via Helm)
helm repo add grafana https://grafana.github.io/helm-charts
helm install alloy grafana/alloy \
  --set-file alloy.configMap.content=config.alloy
```

### Basic Alloy Config (config.alloy)

```river
// =========================================================
// OTLP Receiver - accepts data from instrumented apps
// =========================================================
otelcol.receiver.otlp "default" {
  grpc {
    endpoint = "0.0.0.0:4317"
  }
  http {
    endpoint = "0.0.0.0:4318"
  }
  output {
    metrics = [otelcol.processor.resourcedetection.default.input]
    logs    = [otelcol.processor.resourcedetection.default.input]
    traces  = [otelcol.processor.resourcedetection.default.input]
  }
}

// =========================================================
// Resource Detection - auto-adds cloud/host metadata
// =========================================================
otelcol.processor.resourcedetection "default" {
  // Detect from: env vars, system info, cloud providers
  detectors = ["env", "system", "gcp", "ec2", "azure"]

  system {
    hostname_sources = ["os"]
  }

  output {
    metrics = [otelcol.processor.transform.drop_unneeded.input]
    logs    = [otelcol.processor.transform.drop_unneeded.input]
    traces  = [otelcol.processor.transform.drop_unneeded.input]
  }
}

// =========================================================
// Transform - remove noisy/expensive attributes
// =========================================================
otelcol.processor.transform "drop_unneeded" {
  error_mode = "ignore"

  trace_statements {
    context    = "resource"
    statements = [
      // Remove high-cardinality attributes that increase storage cost
      // "delete_key(attributes, \"process.command_args\")",
    ]
  }

  output {
    metrics = [otelcol.processor.batch.default.input]
    logs    = [otelcol.processor.batch.default.input]
    traces  = [otelcol.processor.batch.default.input]
  }
}

// =========================================================
// Batch Processor - groups signals for efficient export
// =========================================================
otelcol.processor.batch "default" {
  send_batch_size    = 8192
  send_batch_max_size = 0
  timeout            = "200ms"

  output {
    metrics = [otelcol.exporter.otlphttp.grafana_cloud.input]
    logs    = [otelcol.exporter.otlphttp.grafana_cloud.input]
    traces  = [otelcol.exporter.otlphttp.grafana_cloud.input]
  }
}

// =========================================================
// Authentication
// =========================================================
otelcol.auth.basic "grafana_cloud" {
  username = env("GRAFANA_CLOUD_INSTANCE_ID")
  password = env("GRAFANA_CLOUD_API_KEY")
}

// =========================================================
// Export to Grafana Cloud
// =========================================================
otelcol.exporter.otlphttp "grafana_cloud" {
  client {
    endpoint = env("GRAFANA_CLOUD_OTLP_ENDPOINT")
    auth     = otelcol.auth.basic.grafana_cloud.handler
  }
}
```

### Environment Variables for Alloy

```bash
# From Grafana Cloud > My Account > Stack > OpenTelemetry
GRAFANA_CLOUD_OTLP_ENDPOINT=https://otlp-gateway-prod-us-east-0.grafana.net/otlp
GRAFANA_CLOUD_INSTANCE_ID=123456
GRAFANA_CLOUD_API_KEY=glc_eyJ...
```

## Step 3: Direct OTLP to Grafana Cloud (without Alloy)

If you prefer sending directly from your application:

```bash
# In your app's environment
OTEL_EXPORTER_OTLP_ENDPOINT=https://otlp-gateway-<region>.grafana.net/otlp
OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
# Header value: Basic base64("instanceID:apiKey")
OTEL_EXPORTER_OTLP_HEADERS=Authorization=Basic <base64-instanceid:apikey>
OTEL_SERVICE_NAME=my-api
OTEL_RESOURCE_ATTRIBUTES=service.namespace=myteam,deployment.environment=production
```

Get the base64 value:
```bash
echo -n "123456:glc_eyJ..." | base64
```

## Step 4: Span Metrics (How RED Metrics Are Generated)

Application Observability generates RED metrics from traces. This happens in two places:

### Option A: Tempo Metrics-Generator (Grafana Cloud default)

Grafana Cloud Tempo automatically runs the metrics-generator. No configuration needed for basic usage.

Generated metrics:
- `traces_spanmetrics_calls_total` - request rate (labeled by `span_name`, `status_code`, `service_name`)
- `traces_spanmetrics_duration_seconds` - latency histogram
- `traces_service_graph_request_total` - for service map
- `traces_service_graph_request_failed_total` - error count for service map

Span metric dimensions include by default:
- `service.name`
- `service.namespace`
- `deployment.environment`
- `service.version`
- `k8s.cluster.name`
- `cloud.region`

### Option B: OTel Collector Spanmetrics Connector

If using your own OTel Collector:

```yaml
# otelcol-config.yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318

connectors:
  spanmetrics:
    histogram:
      explicit:
        buckets: [1ms, 5ms, 10ms, 25ms, 50ms, 100ms, 250ms, 500ms, 1s, 5s]
    dimensions:
      - name: service.namespace
      - name: deployment.environment
      - name: service.version
      - name: http.method
      - name: http.status_code
    exemplars:
      enabled: true
    namespace: "traces.span"

exporters:
  otlphttp/grafana:
    endpoint: "${GRAFANA_CLOUD_OTLP_ENDPOINT}"
    auth:
      authenticator: basicauth/grafana

  prometheusremotewrite/grafana:
    endpoint: "${GRAFANA_CLOUD_PROMETHEUS_ENDPOINT}"
    auth:
      authenticator: basicauth/grafana

extensions:
  basicauth/grafana:
    client_auth:
      username: "${GRAFANA_CLOUD_INSTANCE_ID}"
      password: "${GRAFANA_CLOUD_API_KEY}"

service:
  extensions: [basicauth/grafana]
  pipelines:
    traces:
      receivers: [otlp]
      exporters: [otlphttp/grafana, spanmetrics]
    metrics/spanmetrics:
      receivers: [spanmetrics]
      exporters: [prometheusremotewrite/grafana]
```

## Span Attributes for Best Results

App Observability uses specific span attributes to populate UI panels:

### HTTP Spans
```
http.method          GET, POST, etc.
http.status_code     200, 404, 500, etc.
http.route           /api/users/{id}
http.url             Full URL (use sparingly - high cardinality)
http.target          /api/users/123
http.scheme          http, https
```

### RPC Spans (gRPC)
```
rpc.system           grpc
rpc.service          mypackage.MyService
rpc.method           GetUser
rpc.grpc.status_code 0 (OK), 2 (UNKNOWN), 13 (INTERNAL), etc.
```

### Database Spans
```
db.system            postgresql, mysql, redis, mongodb
db.name              database name
db.operation         SELECT, INSERT, UPDATE
db.statement         SQL statement (careful with PII)
```

### Messaging Spans
```
messaging.system     kafka, rabbitmq, sqs
messaging.destination topic or queue name
messaging.operation  publish, receive, process
```

## Service Inventory and Service Map

### Service Inventory

Shows all services as a table with columns:
- Service name
- Rate (requests/sec)
- Error rate (%)
- Duration (p95 latency)
- Environment
- Technology badge (auto-detected from `telemetry.sdk.language`)

Filters available:
- Environment (`deployment.environment`)
- Namespace (`service.namespace`)
- Technology

### Service Map

Uses Tempo's `service-graphs` metrics generator:

Nodes = services (sized by request rate)
Edges = calls between services (direction determined by `span.kind`):
- `SPAN_KIND_CLIENT` = outgoing call (source node)
- `SPAN_KIND_SERVER` = incoming call (destination node)

For service map edges to form correctly, your spans need:
- Server spans: `span.kind = SERVER` with `server.address` or `peer.service`
- Client spans: `span.kind = CLIENT` targeting another service

Manual `peer.service` annotation (when automatic detection fails):
```python
with tracer.start_as_current_span("call-payment-service") as span:
    span.set_attribute("peer.service", "payment-api")
    span.set_attribute("span.kind", "CLIENT")
    # ... make the call
```

## Service Overview Page

Each service has a dedicated overview showing:

- **Rate** panel: requests/sec over time (from `traces_spanmetrics_calls_total`)
- **Errors** panel: error rate % (from status code != OK)
- **Duration** panel: p50, p95, p99 latency histograms
- **Operations** panel: top endpoints with individual RED metrics
- **Logs** panel: correlated logs (requires matching `service.name`)
- **Infrastructure** panel: pod/node metrics (requires K8s monitoring)
- **Profiles** button: link to Pyroscope (requires profiling setup)

## Configuring Baselines and Anomaly Detection

App Observability can show baseline metrics (ML-based) for anomaly highlighting:

Requirements:
- `deployment.environment` attribute must be set
- Minimum 2 weeks of data for baseline training
- Enable in Grafana Cloud > Application Observability > Settings

## Alert Rules for APM

Pre-built alert rules available in App Observability:
- High error rate (> threshold % of requests)
- High latency (p95 > SLO)
- Low request rate (sudden drops = potential outage)

Create custom PromQL alerts against span metrics:

```promql
# Error rate > 5% for any service
(
  sum by (service_name) (rate(traces_spanmetrics_calls_total{status_code="STATUS_CODE_ERROR"}[5m]))
  /
  sum by (service_name) (rate(traces_spanmetrics_calls_total[5m]))
) > 0.05

# p95 latency > 500ms
histogram_quantile(0.95,
  sum by (le, service_name) (
    rate(traces_spanmetrics_duration_seconds_bucket[5m])
  )
) > 0.5
```

## SLO Configuration

App Observability integrates with Grafana Cloud SLOs:

1. Navigate to Service Overview
2. Click "Create SLO" button
3. Select metric type: Availability (error rate) or Latency
4. Set target (e.g., 99.9% availability) and window (e.g., 28 days)
5. SLO dashboard auto-generates with error budget burn rate alerts

## Sampling Considerations

IMPORTANT: Generate span metrics BEFORE sampling. App Observability requires complete, unsampled trace data for accurate RED metrics.

Recommended pipeline with tail sampling:
```
App -> Alloy (receive all traces) -> Span Metrics (computed here) -> Tail Sampler -> Export samples to Tempo
                                          |
                                          v
                                   Grafana Mimir (all RED metrics, not just sampled)
```

In Alloy config:
```river
// Generate metrics from ALL traces before sampling
otelcol.connector.spanmetrics "default" {
  // dimensions...
  output {
    metrics = [otelcol.exporter.otlphttp.grafana_cloud.input]
  }
}

// Then apply tail sampling for trace storage cost control
otelcol.processor.tail_sampling "default" {
  decision_wait = "10s"
  policies = [
    { name = "errors", type = "status_code", status_code = { status_codes = ["ERROR"] } },
    { name = "slow",   type = "latency",     latency     = { threshold_ms = 500 } },
    { name = "sample", type = "probabilistic", probabilistic = { sampling_percentage = 10 } },
  ]
  output {
    traces = [otelcol.exporter.otlphttp.grafana_cloud.input]
  }
}
```

## Kubernetes Deployment

### Alloy as DaemonSet (recommended)

Running Alloy on every node enables host-level resource detection:

```yaml
# alloy-daemonset.yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: alloy
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app: alloy
  template:
    metadata:
      labels:
        app: alloy
    spec:
      containers:
        - name: alloy
          image: grafana/alloy:latest
          args:
            - run
            - /etc/alloy/config.alloy
          ports:
            - containerPort: 4317  # OTLP gRPC
              hostPort: 4317
            - containerPort: 4318  # OTLP HTTP
              hostPort: 4318
          env:
            - name: GRAFANA_CLOUD_OTLP_ENDPOINT
              valueFrom:
                secretKeyRef:
                  name: grafana-cloud-creds
                  key: otlp-endpoint
            - name: GRAFANA_CLOUD_INSTANCE_ID
              valueFrom:
                secretKeyRef:
                  name: grafana-cloud-creds
                  key: instance-id
            - name: GRAFANA_CLOUD_API_KEY
              valueFrom:
                secretKeyRef:
                  name: grafana-cloud-creds
                  key: api-key
          volumeMounts:
            - name: alloy-config
              mountPath: /etc/alloy
      volumes:
        - name: alloy-config
          configMap:
            name: alloy-config
```

### Application Pod Configuration

Point pods to the node-local Alloy instance:

```yaml
env:
  - name: OTEL_EXPORTER_OTLP_ENDPOINT
    value: "http://$(HOST_IP):4317"
  - name: HOST_IP
    valueFrom:
      fieldRef:
        fieldPath: status.hostIP
  - name: OTEL_SERVICE_NAME
    value: "my-api"
  - name: OTEL_RESOURCE_ATTRIBUTES
    value: "service.namespace=my-team,deployment.environment=production,k8s.pod.name=$(POD_NAME),k8s.namespace.name=$(NAMESPACE)"
  - name: POD_NAME
    valueFrom:
      fieldRef:
        fieldPath: metadata.name
  - name: NAMESPACE
    valueFrom:
      fieldRef:
        fieldPath: metadata.namespace
```

## Traces to Logs Correlation

For App Observability to show correlated logs in the Service Overview:

1. Inject trace context into log output
2. Use structured logging with `traceId` and `spanId` fields
3. Ensure logs have `service.name` label matching the OTel `service.name`

Example (Node.js with pino):
```javascript
const { trace } = require('@opentelemetry/api');

// In your logging middleware/utility:
function getTraceContext() {
  const span = trace.getActiveSpan();
  if (!span) return {};
  const { traceId, spanId } = span.spanContext();
  return { traceId, spanId };
}

logger.info({ ...getTraceContext(), userId: '123' }, 'User logged in');
// Output: {"traceId":"abc123","spanId":"def456","userId":"123","msg":"User logged in"}
```

Alloy can then extract these fields for Loki:
```river
loki.process "extract_trace" {
  stage.json {
    expressions = {
      traceId = "traceId",
      spanId  = "spanId",
    }
  }
  stage.labels {
    values = {
      traceId = "",
      spanId  = "",
    }
  }
  forward_to = [loki.write.grafana_cloud.receiver]
}
```

## Troubleshooting

### Service Not Appearing in Inventory

Check:
1. `service.name` resource attribute is set - this is mandatory
2. Traces are actually arriving in Tempo (check Explore > Tempo)
3. Span metrics are being generated (check Explore > Mimir, query `traces_spanmetrics_calls_total`)
4. `deployment.environment` is set (required for some views)

### Service Map Has Missing Connections

Check:
1. `span.kind` is set on spans (CLIENT for outgoing, SERVER for incoming)
2. `peer.service` is set on client spans (Alloy/Tempo uses this to create edges)
3. Service-graphs metrics generator is enabled (it is in Grafana Cloud by default)

### RED Metrics Show Wrong Values

Check:
1. Span metrics use `deployment.environment` (dotted) as source - not sanitized `deployment_environment`
2. Sampling is happening AFTER span metrics generation (not before)
3. Clock skew between services is not too large (affects histogram accuracy)

### Log Correlation Not Working

Check:
1. Log labels in Loki include `service_name` matching the OTel `service.name`
2. Loki data source is configured in Grafana
3. App Observability data source settings point to correct Loki instance

## Key Metric Names Reference

| Metric | Source | Description |
|---|---|---|
| `traces_spanmetrics_calls_total` | Tempo | Request count by service/operation |
| `traces_spanmetrics_duration_seconds` | Tempo | Latency histogram |
| `traces_spanmetrics_duration_seconds_bucket` | Tempo | Latency histogram buckets |
| `traces_service_graph_request_total` | Tempo | Service-to-service calls |
| `traces_service_graph_request_failed_total` | Tempo | Failed service-to-service calls |
| `traces_service_graph_request_server_seconds` | Tempo | Server-side latency for service graph |
| `traces_span_metrics_calls_total` | OTel Collector | Same as above (different source) |
| `traces_span_metrics_duration_seconds` | OTel Collector | Same as above (different source) |

Common labels on span metrics:
- `service_name` - from `service.name` attribute
- `span_name` - operation name (e.g., `GET /api/users`)
- `span_kind` - SERVER, CLIENT, etc.
- `status_code` - `STATUS_CODE_OK`, `STATUS_CODE_ERROR`, `STATUS_CODE_UNSET`
- `deployment_environment` - from `deployment.environment`

## References

- Application Observability: https://grafana.com/docs/grafana-cloud/monitor-applications/application-observability/
- Setup guide: https://grafana.com/docs/grafana-cloud/monitor-applications/application-observability/setup/
- Resource attributes: https://grafana.com/docs/grafana-cloud/monitor-applications/application-observability/setup/resource-attributes/
- Metrics and labels: https://grafana.com/docs/grafana-cloud/monitor-applications/application-observability/setup/metrics-labels/
- Alloy for OTel: https://grafana.com/docs/opentelemetry/collector/grafana-alloy/
- OTel semantic conventions: https://opentelemetry.io/docs/specs/semconv/
- Span metrics processor: https://grafana.com/docs/tempo/latest/metrics-from-traces/span-metrics/
