# AI Observability — LLM / model monitoring

Built on OTel GenAI semantic conventions + OpenLIT.

## What it monitors

- LLM API calls (OpenAI, Anthropic, Cohere, Google, etc.)
- Vector DBs (Pinecone, Weaviate, Chroma, …)
- AI frameworks (LangChain, CrewAI, LlamaIndex)
- Model Context Protocol (MCP) servers
- GPU utilization
- Evaluation quality (hallucination, toxicity, bias)

## Key metrics (OTel GenAI)

| Metric | Description |
|---|---|
| `gen_ai_usage_input_tokens_total` | Input / prompt tokens |
| `gen_ai_usage_output_tokens_total` | Output / completion tokens |
| `gen_ai_usage_cost_USD_sum` | Total USD cost |
| `gen_ai_client_operation_duration` | Per-call latency histogram |
| `gen_ai_client_token_usage` | Token-usage histogram |

Trace spans capture `gen_ai.request.model`, temperature/top_p, prompts/completions (configurable), `gen_ai.system`, time-to-first-token.

## Python install + init

```bash
pip install openlit==1.42.0 openai==2.41.0 anthropic==0.105.2 cohere==7.0.3
```

```python
import openlit
openlit.init(application_name="my-ai-app", environment="production")

# Existing LLM code works unchanged
import openai
client = openai.OpenAI()
client.chat.completions.create(
    model="gpt-4", messages=[{"role":"user","content":"Hello!"}])
```

## OTel env vars

```bash
export OTEL_SERVICE_NAME="my-ai-app"
export OTEL_DEPLOYMENT_ENVIRONMENT="production"
export OTEL_EXPORTER_OTLP_ENDPOINT="https://otlp-gateway-<region>.grafana.net/otlp"
# Basic auth: base64(instanceID:apiToken)
export OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic <base64>"
```

Credentials: **My Account → Stack → OpenTelemetry**.

## Evals + guards

```python
evals = openlit.evals.Hallucination(provider="openai", api_key=os.getenv("OPENAI_API_KEY"))
evals.measure(prompt=user_message, contexts=["..."], text=llm_answer)

guard = openlit.guard.All(provider="openai", api_key=os.getenv("OPENAI_API_KEY"))
guard.detect(text=user_message)
```

## Pre-built dashboards (auto-populated)

1. GenAI Observability — rates, latency percentiles, costs
2. GenAI Evaluations — hallucination / bias / toxicity scores
3. Vector Database Observability
4. MCP Observability
5. GPU Monitoring

## Setup

1. Cloud → **Connections** → "AI Observability"
2. UI wizard → OTLP endpoint + API key
3. Set env vars
4. `pip install openlit==1.42.0` + `openlit.init()` at app startup
5. Deploy — dashboards populate within minutes
