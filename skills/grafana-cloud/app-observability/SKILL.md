---
name: app-observability
license: Apache-2.0
description: >
  Grafana Cloud Application Observability (APM), Frontend Observability (RUM/Faro), and AI Observability.
  Covers RED metrics (Rate/Error/Duration), service maps, span metrics from traces, Faro JavaScript/React
  SDK for browser instrumentation, session replay, AI/LLM model monitoring, and integration with
  traces/logs/profiles for full-stack correlation. Use when setting up APM, configuring frontend monitoring,
  analyzing service performance, or monitoring AI/LLM applications.
---

# Grafana Cloud Application Observability Skill

## Overview

Grafana Cloud provides three tightly related application monitoring products:

1. **Application Observability (APM)** - RED metrics from OTel traces, service inventory, service maps
2. **Frontend Observability** - RUM/Faro SDK for browser apps, session replay, web vitals
3. **AI Observability** - LLM/model monitoring via OpenLIT + OTel, token/cost/latency metrics

All three integrate with Grafana Tempo (traces), Loki (logs), and Pyroscope (profiles) for full-stack correlation.

---

## Application Observability (APM)

### What It Is

Application Observability is a pre-built APM experience in Grafana Cloud built on top of OpenTelemetry. It generates RED (Rate, Error, Duration) metrics from distributed traces via span metrics, then surfaces them in:

- **Service Inventory** - table of all services with RED metrics at a glance
- **Service Overview** - per-service RED metrics, top operations, error breakdown
- **Service Map** - node graph of service dependencies with flow visualization
- **Operations view** - per-endpoint RED metrics with p50/p95/p99 latency

### How Metrics Are Generated

Application Observability does NOT rely on traditional Prometheus scraping. Metrics come from **span metrics** - aggregations computed from OTel trace data:

- Source: OTel traces sent to Grafana Tempo or Grafana Alloy
- Generation method: Tempo's metrics-generator OR the `spanmetrics` connector in Alloy/OTel Collector
- Result: Prometheus-compatible metrics stored in Grafana Mimir

Key generated metric names:
- Via Tempo metrics-generator: `traces_spanmetrics_calls_total`, `traces_spanmetrics_duration_seconds`
- Via OTel Collector spanmetrics connector: `traces_span_metrics_calls_total`, `traces_span_metrics_duration_seconds`

### Required OTel Resource Attributes

These attributes MUST be present on all spans for Application Observability to work:

| Attribute | Grafana Label | Purpose |
|---|---|---|
| `service.name` | `service_name` / part of `job` | Identifies the service |
| `service.namespace` | part of `job` label | Groups services; `job = namespace/service.name` |
| `deployment.environment` | `deployment_environment` | Env filter (prod/dev/staging) |

The `job` label is constructed as:
- `service.namespace/service.name` when namespace is set
- `service.name` alone when no namespace

Additional recommended attributes:
- `service.version` - shown in service overview
- `k8s.cluster.name` - for K8s environments
- `k8s.namespace.name` - Kubernetes namespace
- `cloud.region` - for multi-region setups

### Setting Environment Variables for OTel SDK

```bash
export OTEL_SERVICE_NAME="my-api"
export OTEL_RESOURCE_ATTRIBUTES="service.namespace=myteam,deployment.environment=production,service.version=1.2.3"
export OTEL_EXPORTER_OTLP_ENDPOINT="http://localhost:4317"
export OTEL_EXPORTER_OTLP_PROTOCOL="grpc"
```

### Grafana Alloy Configuration (River syntax)

Alloy acts as a local OTel Collector and forwards data to Grafana Cloud:

```river
// Receive traces, metrics, logs from instrumented apps
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

// Auto-detect host/cloud metadata
otelcol.processor.resourcedetection "default" {
  detectors = ["env", "system", "gcp", "aws", "azure"]
  output {
    metrics = [otelcol.processor.batch.default.input]
    logs    = [otelcol.processor.batch.default.input]
    traces  = [otelcol.processor.batch.default.input]
  }
}

// Batch for efficiency
otelcol.processor.batch "default" {
  output {
    metrics = [otelcol.exporter.otlphttp.grafana_cloud.input]
    logs    = [otelcol.exporter.otlphttp.grafana_cloud.input]
    traces  = [otelcol.exporter.otlphttp.grafana_cloud.input]
  }
}

// Auth
otelcol.auth.basic "grafana_cloud" {
  username = env("GRAFANA_CLOUD_INSTANCE_ID")
  password = env("GRAFANA_CLOUD_API_KEY")
}

// Export to Grafana Cloud OTLP endpoint
otelcol.exporter.otlphttp "grafana_cloud" {
  client {
    endpoint = env("GRAFANA_CLOUD_OTLP_ENDPOINT")
    auth     = otelcol.auth.basic.grafana_cloud.handler
  }
}
```

Required environment variables for Alloy:
```bash
GRAFANA_CLOUD_OTLP_ENDPOINT=https://otlp-gateway-<region>.grafana.net/otlp
GRAFANA_CLOUD_INSTANCE_ID=<your-instance-id>
GRAFANA_CLOUD_API_KEY=<your-api-key>
```

### Service Map

The Service Map uses Tempo's **metrics-generator** to produce service graph metrics:
- Node graph shows services as nodes, HTTP/gRPC calls as edges
- Edge thickness indicates request rate; color indicates error rate
- Clicking a node navigates to Service Overview
- Requires `span.kind` (CLIENT/SERVER) on spans for directional edges

Enable in Tempo (managed by Grafana Cloud automatically):
- `service-graphs` metrics generator enabled by default in Grafana Cloud Tempo
- Uses `traces_service_graph_request_total`, `traces_service_graph_request_failed_total` metrics

### Integration with Traces, Logs, Profiles

Application Observability provides one-click correlation:
- **Traces**: Click any metric spike to open exemplar traces in Grafana Tempo
- **Logs**: Service logs shown in Service Overview; correlated via `service.name` label
- **Profiles**: "Go to profiles" button in Service Overview when Pyroscope is configured
- **Frontend**: Link from Application Observability to Frontend Observability for the same service

---

## Frontend Observability (Faro)

### What It Is

Grafana Faro is an open-source JavaScript/TypeScript SDK for **Real User Monitoring (RUM)**. It instruments browser applications to capture:

- **Web vitals**: Core Web Vitals (LCP, CLS, INP) and additional performance metrics
- **Errors**: Unhandled exceptions, rejected promises with stack traces
- **Sessions**: User journeys, page views, navigation timing
- **Logs**: Custom log messages from frontend code
- **Traces**: Distributed traces via OpenTelemetry-JS (correlates with backend spans)
- **Session replay**: Rrweb-based DOM recording for reproducing user issues

Data flows: Faro SDK -> Grafana Alloy (faro receiver) OR Grafana Cloud OTLP endpoint -> Loki (logs) + Tempo (traces) + Mimir (metrics)

### Faro SDK Packages

```
@grafana/faro-core          # Core SDK - signals, transports, API
@grafana/faro-web-sdk       # Web instrumentations + transports
@grafana/faro-web-tracing   # OpenTelemetry-JS distributed tracing
@grafana/faro-react         # React-specific integrations (error boundary, router)
```

### Basic JavaScript Setup (npm)

```bash
npm install @grafana/faro-web-sdk
# or
yarn add @grafana/faro-web-sdk
```

```javascript
import {
  initializeFaro,
  getWebInstrumentations,
} from '@grafana/faro-web-sdk';

const faro = initializeFaro({
  url: 'https://faro-collector-prod-<region>.grafana.net/collect/<app-key>',
  app: {
    name: 'my-frontend-app',
    version: '1.0.0',
    environment: 'production',
  },
  instrumentations: [
    ...getWebInstrumentations({
      captureConsole: true,
    }),
  ],
});

// Manual API usage
faro.api.pushLog(['User clicked checkout button']);
faro.api.pushError(new Error('Payment failed'));
faro.api.pushEvent('button_click', { button: 'checkout' });
```

### CDN Setup (no bundler)

```html
<script src="https://unpkg.com/@grafana/faro-web-sdk@latest/dist/library/faro-web-sdk.iife.js"></script>
<script>
  const { initializeFaro, getWebInstrumentations } = GrafanaFaroWebSdk;

  initializeFaro({
    url: 'https://faro-collector-prod-<region>.grafana.net/collect/<app-key>',
    app: { name: 'my-app', version: '1.0.0' },
    instrumentations: [...getWebInstrumentations()],
  });
</script>
```

### React Setup with Tracing

```bash
npm install @grafana/faro-react @grafana/faro-web-tracing
```

```javascript
import { initializeFaro, getWebInstrumentations } from '@grafana/faro-web-sdk';
import { TracingInstrumentation } from '@grafana/faro-web-tracing';
import {
  createReactRouterV6DataOptions,
  ReactIntegration,
  withFaroRouterInstrumentation,
} from '@grafana/faro-react';
import { createBrowserRouter, RouterProvider } from 'react-router-dom';

const faro = initializeFaro({
  url: 'https://faro-collector-prod-<region>.grafana.net/collect/<app-key>',
  app: {
    name: 'my-react-app',
    version: '1.0.0',
    environment: 'production',
  },
  instrumentations: [
    ...getWebInstrumentations({ captureConsole: true }),
    new TracingInstrumentation(),
    new ReactIntegration({
      router: createReactRouterV6DataOptions({}),
    }),
  ],
});

const router = withFaroRouterInstrumentation(
  createBrowserRouter([
    { path: '/', element: <Home /> },
    { path: '/about', element: <About /> },
  ])
);

function App() {
  return <RouterProvider router={router} />;
}
```

### Session Configuration

```javascript
initializeFaro({
  url: '...',
  app: { name: 'my-app' },
  sessionTracking: {
    enabled: true,
    persistent: true,
    maxSessionPersistenceTime: 4 * 60 * 60 * 1000, // 4 hours in ms
    samplingRate: 1,           // 1 = 100%, 0.5 = 50% of sessions
    onSessionChange: (oldSession, newSession) => {
      console.log('Session changed', newSession.id);
    },
  },
  instrumentations: [...getWebInstrumentations()],
});
```

### Getting the Collector URL

1. In Grafana Cloud, go to **Connections** (left menu) > search "Frontend Observability"
2. Click the Frontend Observability card
3. Navigate to **Web SDK Configuration** tab
4. Copy the `url` value - this is your unique collector endpoint
5. Paste into your `initializeFaro({ url: '...' })` call

### What Faro Captures Automatically

When using `getWebInstrumentations()`:
- Page views and navigation timing
- Core Web Vitals (LCP, CLS, INP - replaces FID in Faro v2)
- JavaScript errors and unhandled rejections
- Console errors/warnings (when `captureConsole: true`)
- Resource loading performance
- User interactions (clicks, form events)
- Fetch/XHR request timing

### Correlation with Backend Traces

When `TracingInstrumentation` is included, Faro:
- Injects `traceparent` / `tracestate` headers into outgoing fetch/XHR requests
- Creates spans for each HTTP call
- Links browser session to backend traces in Tempo
- Enables "Frontend to Backend" trace waterfall in Grafana

---

## AI Observability

### What It Is

AI Observability monitors generative AI and LLM applications in production. Built on OTel GenAI semantic conventions and the **OpenLIT** instrumentation library.

Monitors:
- LLM API calls (OpenAI, Anthropic, Cohere, Google, etc.)
- Vector databases (Pinecone, Weaviate, Chroma, etc.)
- AI frameworks (LangChain, CrewAI, LlamaIndex)
- Model Context Protocol (MCP) servers
- GPU utilization
- AI evaluation quality (hallucination, toxicity, bias)

### Key Metrics (OTel GenAI Semantic Conventions)

| Metric | Description |
|---|---|
| `gen_ai_usage_input_tokens_total` | Total input/prompt tokens consumed |
| `gen_ai_usage_output_tokens_total` | Total output/completion tokens consumed |
| `gen_ai_usage_cost_USD_sum` | Total cost in USD |
| `gen_ai_client_operation_duration` | Latency per LLM call (histogram) |
| `gen_ai_client_token_usage` | Token usage histogram |

Trace spans capture:
- Model name (`gen_ai.request.model`)
- Temperature, top_p parameters
- Full prompts and completions (configurable)
- Provider (`gen_ai.system`: `openai`, `anthropic`, etc.)
- Time to first token (TTFT)

### Python Setup with OpenLIT

```bash
pip install openlit openai anthropic cohere
```

```python
import openlit
import openai

# One-line initialization - auto-instruments all supported LLM libraries
openlit.init()

# Optional parameters
openlit.init(
    application_name="my-ai-app",
    environment="production",
)

# Your existing code works unchanged - OpenLIT intercepts all LLM calls
client = openai.OpenAI()
response = client.chat.completions.create(
    model="gpt-4",
    messages=[{"role": "user", "content": "Hello!"}]
)
```

### OTel Environment Variables

```bash
export OTEL_SERVICE_NAME="my-ai-app"
export OTEL_DEPLOYMENT_ENVIRONMENT="production"
export OTEL_EXPORTER_OTLP_ENDPOINT="https://otlp-gateway-<region>.grafana.net/otlp"
# Base64 encode "instanceID:apiToken"
export OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic <base64-encoded-instanceid:apitoken>"
```

To get the credentials:
1. In Grafana Cloud, go to **My Account** > **Stack** > **OpenTelemetry**
2. Generate a token and copy the OTLP endpoint

### AI Evaluations and Guards

```python
# Hallucination detection
evals = openlit.evals.Hallucination(
    provider="openai",
    api_key=os.getenv("OPENAI_API_KEY")
)
result = evals.measure(
    prompt=user_message,
    contexts=["Your knowledge base content here"],
    text=llm_answer
)

# Content safety guard
guard = openlit.guard.All(
    provider="openai",
    api_key=os.getenv("OPENAI_API_KEY")
)
guard.detect(text=user_message)
```

### Prebuilt Dashboards

Once metrics arrive, Grafana Cloud auto-populates five dashboards:
1. **GenAI Observability** - request rates, latency percentiles, costs
2. **GenAI Evaluations** - hallucination, bias, toxicity scores
3. **Vector Database Observability** - query latency, index ops
4. **MCP Observability** - tool call rates, errors
5. **GPU Monitoring** - utilization, memory, temperature

### Setup Path

1. In Grafana Cloud: **Connections** > search "AI Observability" > click the card
2. Follow the UI wizard to get your OTLP endpoint and API key
3. Set the environment variables
4. `pip install openlit` and call `openlit.init()` at app startup
5. Deploy - dashboards populate automatically within minutes

---

## Full-Stack Correlation Summary

| Signal | Product | Storage | Query Language |
|---|---|---|---|
| Metrics (RED) | App Observability | Mimir | PromQL |
| Traces | Tempo | Tempo | TraceQL |
| Logs | Loki | Loki | LogQL |
| Profiles | Pyroscope | Pyroscope | - |
| Browser RUM | Faro/Frontend Obs | Loki + Tempo | - |
| LLM metrics | AI Observability | Mimir | PromQL |

Correlation keys:
- `service.name` / `service_name` links all signals for a service
- Trace exemplars embed trace IDs in metric data points (RED metrics -> traces)
- `traceID` in logs enables log-to-trace correlation
- `profileID` / time range enables trace-to-profile correlation
- Faro injects `traceparent` headers to link browser sessions to backend traces

---

## Common Tasks

### Find Why a Service Has High Latency

1. **App Observability** > Service Inventory > click service
2. In Service Overview: check p95/p99 latency trend in Operations panel
3. Click a high-latency operation > "View traces" to open exemplar traces in Tempo
4. In Tempo trace: use "Go to profiles" to see CPU profile at that time
5. Check correlated logs in the Logs panel of Service Overview

### Debug a Frontend Error

1. **Frontend Observability** > Errors panel > click error
2. View stack trace, browser, OS, session info
3. Click "View session replay" to see what the user did
4. Check correlated backend trace if `TracingInstrumentation` is configured

### Monitor LLM Cost Drift

1. **AI Observability** dashboard > GenAI Observability
2. Use `gen_ai_usage_cost_USD_sum` metric to see cost by model/provider
3. Set alert on cost threshold or token usage spike
4. Drill into traces to see which prompts are consuming the most tokens

---

## References

- App Observability docs: https://grafana.com/docs/grafana-cloud/monitor-applications/application-observability/
- Frontend Observability docs: https://grafana.com/docs/grafana-cloud/monitor-applications/frontend-observability/
- Faro Web SDK GitHub: https://github.com/grafana/faro-web-sdk
- AI Observability docs: https://grafana.com/docs/grafana-cloud/monitor-applications/ai-observability/
- Alloy for App Observability: https://grafana.com/docs/opentelemetry/collector/grafana-alloy/
- OpenLIT: https://openlit.io/
