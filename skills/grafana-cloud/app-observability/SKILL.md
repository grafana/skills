---
name: app-observability
license: Apache-2.0
description: Get RED metrics + service maps + frontend RUM + AI/LLM monitoring out of Grafana Cloud — Application Observability (`traces_spanmetrics_*` from OTel traces, p50/p95/p99 latency, exemplar-to-trace, traces-to-logs / profiles), Frontend Observability with the Faro Web SDK (Core Web Vitals, session replay, `pushError`, React + router integration, `TracingInstrumentation` for browser → backend trace correlation), and AI Observability via OpenLIT (token / cost / latency, GPU, hallucination + toxicity evals). Use when standing up APM for a service, wiring an Alloy OTLP receiver + forwarding to Cloud, instrumenting a React frontend for RUM, debugging why service-map edges are missing, monitoring LLM cost drift, or correlating a frontend error to its backend trace — even when the user says "set up APM", "show service map", "monitor browser perf", "session replay", "RUM SDK", or "watch our OpenAI bill" without naming App / Frontend / AI Observability.
---

# Grafana Cloud Application Observability

> **Docs**: https://grafana.com/docs/grafana-cloud/monitor-applications/

Three products that share the same OTLP + Mimir / Loki / Tempo / Pyroscope plumbing:

1. **Application Observability** — APM from OTel spanmetrics
2. **Frontend Observability** — Faro Web SDK, RUM + session replay
3. **AI Observability** — LLM / vector-DB monitoring via OpenLIT

## Prerequisites

- Grafana Cloud stack + OTLP endpoint + numeric instance ID + API key with `MetricsPublisher` + `LogsPublisher` + `TracesPublisher`
- For APM: app instrumented with OTel SDK; for Frontend: a web app + Faro app key; for AI: Python ≥ 3.10
- Grafana Alloy as the local OTLP receiver (recommended)

## Common Workflows

### 1. Stand up APM — Alloy receiver → Grafana Cloud + verify

```bash
# 1. Set Cloud creds + start Alloy with config from references/apm.md
export GRAFANA_CLOUD_OTLP_ENDPOINT=https://otlp-gateway-prod-us-east-0.grafana.net/otlp
export GRAFANA_CLOUD_INSTANCE_ID=123456
export GRAFANA_CLOUD_API_KEY=glc_eyJ...
alloy fmt /etc/alloy/config.alloy   # syntax check
alloy run /etc/alloy/config.alloy

# 2. Verify Alloy is receiving + forwarding
curl -s http://localhost:12345/api/v0/web/components \
  | jq '.[] | select(.id|test("otelcol\\.exporter\\.otlphttp"))
        | {id, health:.health.state}'
# Expect health.state == "healthy"
curl -s http://localhost:12345/metrics \
  | grep -E 'otelcol_(receiver_accepted_spans|exporter_sent_spans)'

# 3. Point your app at Alloy (with required attributes!)
export OTEL_SERVICE_NAME="my-api"
export OTEL_RESOURCE_ATTRIBUTES="service.namespace=myteam,deployment.environment=production"
export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317
export OTEL_EXPORTER_OTLP_PROTOCOL=grpc

# 4. Verify spans landed in Tempo + spanmetrics generated
#    Tempo (TraceQL):  { resource.service.name = "my-api" }
#    Mimir (PromQL):   sum by (job) (rate(traces_spanmetrics_calls_total{service_name="my-api"}[5m]))
#    Expect > 0 within ~1 minute.

# 5. Verify it's wired to App Observability
#    Grafana → Application → Service Inventory: "my-api" should appear with RED metrics
#    Click into it → Service Map edges visible (requires span.kind on outbound calls)
```

Full Alloy block + required resource attributes + spanmetric names + correlation links: [`references/apm.md`](references/apm.md).

### 2. Instrument a React frontend with Faro

```bash
# 1. Install
npm install @grafana/faro-react @grafana/faro-web-tracing
```

```javascript
// 2. initializeFaro with TracingInstrumentation + ReactIntegration (see references/faro.md)
//    Push a smoketest event so we have a known signal:
faro.api.pushEvent('faro_smoketest', { ts: Date.now().toString() });
```

```bash
# 3. Verify in DevTools Network — POST to /collect returns 202
#    (401 → wrong app key; 404 → wrong url region)

# 4. Verify in Grafana Cloud
#    - Frontend Observability → your app → Sessions: your session appears
#    - LogQL on Loki: {kind="event"} |= "faro_smoketest"
#    - With TracingInstrumentation: open the session → the trace ID links to Tempo
```

Full React example, CDN setup, session config: [`references/faro.md`](references/faro.md).

### 3. Add AI / LLM observability

```bash
pip install openlit==1.42.0
```

```python
# At app startup
import openlit
openlit.init(application_name="my-ai-app", environment="production")
# Your existing OpenAI / Anthropic / Cohere calls now emit OTel spans + metrics.
```

```bash
# Env (same OTLP endpoint as APM)
export OTEL_SERVICE_NAME="my-ai-app"
export OTEL_EXPORTER_OTLP_ENDPOINT="https://otlp-gateway-<region>.grafana.net/otlp"
export OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic $(echo -n $ID:$KEY | base64)"

# Verify after a few LLM calls:
#   PromQL: sum by (gen_ai_request_model) (rate(gen_ai_usage_input_tokens_total[5m]))
#   Dashboard: Grafana → AI Observability → "GenAI Observability" auto-populates
```

Full OpenLIT install, evals/guards, GenAI metric list, dashboard names: [`references/ai-observability.md`](references/ai-observability.md).

## Full-stack correlation cheat sheet

| Signal | Product | Storage | Query |
|---|---|---|---|
| RED metrics | App Observability | Mimir | PromQL |
| Traces | Tempo | Tempo | TraceQL |
| Logs | Loki | Loki | LogQL |
| Profiles | Pyroscope | Pyroscope | ProfileQL |
| Browser RUM | Frontend Observability | Loki + Tempo | LogQL / TraceQL |
| LLM metrics | AI Observability | Mimir | PromQL |

Correlation keys: `service.name` joins all signals; trace exemplars embed trace IDs in metric points; `traceID` in logs and `traceparent` injected by Faro for FE → BE linking.

## Troubleshooting

- Service missing from Service Inventory → missing `service.namespace` (job label) or `deployment.environment` resource attribute
- Service Map edges missing → `span.kind` not set on outbound calls (must be CLIENT) or inbound (SERVER)
- Faro `/collect` returns 401 → wrong app key; 404 → region in URL doesn't match the Faro app
- No GenAI metrics → confirm OpenLIT version matches OTel semantic-conv version expected by Cloud; verify auth with curl as in workflow #3

## References

- [`references/apm.md`](references/apm.md) — APM essentials: how RED metrics are generated, required OTel resource attributes, Alloy config, correlation links
- [`references/apm-setup.md`](references/apm-setup.md) — deep dive: full per-language OTel SDK setup (Node / Python / Java / Go), span-metrics options, complete Alloy config
- [`references/faro.md`](references/faro.md) — Faro essentials: SDK init, instrumentations, session replay
- [`references/frontend-observability.md`](references/frontend-observability.md) — deep dive: full Faro SDK reference, React/Vue/Angular integration, custom events, source maps
- [`references/ai-observability.md`](references/ai-observability.md) — OpenLIT auto-instrumentation for OpenAI / Anthropic / Bedrock / Vertex AI

## Resources

- [App Observability docs](https://grafana.com/docs/grafana-cloud/monitor-applications/application-observability/)
- [Frontend Observability docs](https://grafana.com/docs/grafana-cloud/monitor-applications/frontend-observability/)
- [Faro Web SDK](https://github.com/grafana/faro-web-sdk)
- [AI Observability docs](https://grafana.com/docs/grafana-cloud/monitor-applications/ai-observability/)
- [OpenLIT](https://openlit.io/)
