# Language-Specific OTel SDK Instrumentation

## Go

### Requirements
- Go 1.22+

### Dependencies

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

### otel.go - SDK Setup

```go
package main

import (
    "context"
    "errors"
    "time"

    "go.opentelemetry.io/contrib/instrumentation/runtime"
    "go.opentelemetry.io/otel"
    "go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetrichttp"
    "go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp"
    "go.opentelemetry.io/otel/propagation"
    sdkmetric "go.opentelemetry.io/otel/sdk/metric"
    "go.opentelemetry.io/otel/sdk/resource"
    sdktrace "go.opentelemetry.io/otel/sdk/trace"
    semconv "go.opentelemetry.io/otel/semconv/v1.21.0"
)

func setupOTelSDK(ctx context.Context) (shutdown func(context.Context) error, err error) {
    var shutdownFuncs []func(context.Context) error

    shutdown = func(ctx context.Context) error {
        var err error
        for _, fn := range shutdownFuncs {
            err = errors.Join(err, fn(ctx))
        }
        shutdownFuncs = nil
        return err
    }

    handleErr := func(inErr error) {
        err = errors.Join(inErr, shutdown(ctx))
    }

    // Set up propagator
    prop := propagation.NewCompositeTextMapPropagator(
        propagation.TraceContext{},
        propagation.Baggage{},
    )
    otel.SetTextMapPropagator(prop)

    // Resource
    res, err := resource.New(ctx,
        resource.WithFromEnv(),
        resource.WithProcess(),
        resource.WithOS(),
        resource.WithContainer(),
        resource.WithHost(),
        resource.WithAttributes(
            semconv.ServiceName("myapp"),
        ),
    )
    if err != nil {
        handleErr(err)
        return
    }

    // Trace exporter
    traceExporter, err := otlptracehttp.New(ctx)
    if err != nil {
        handleErr(err)
        return
    }

    tracerProvider := sdktrace.NewTracerProvider(
        sdktrace.WithBatcher(traceExporter),
        sdktrace.WithResource(res),
    )
    shutdownFuncs = append(shutdownFuncs, tracerProvider.Shutdown)
    otel.SetTracerProvider(tracerProvider)

    // Metric exporter
    metricExporter, err := otlpmetrichttp.New(ctx)
    if err != nil {
        handleErr(err)
        return
    }

    meterProvider := sdkmetric.NewMeterProvider(
        sdkmetric.WithReader(
            sdkmetric.NewPeriodicReader(metricExporter,
                sdkmetric.WithInterval(30*time.Second),
            ),
        ),
        sdkmetric.WithResource(res),
    )
    shutdownFuncs = append(shutdownFuncs, meterProvider.Shutdown)
    otel.SetMeterProvider(meterProvider)

    // Start Go runtime metrics collection
    if err = runtime.Start(runtime.WithMinimumReadMemStatsInterval(time.Second)); err != nil {
        handleErr(err)
        return
    }

    return
}
```

### main.go - HTTP Server with Instrumentation

```go
package main

import (
    "context"
    "log"
    "net/http"
    "os/signal"
    "syscall"
    "time"

    "go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
)

func main() {
    // Handle SIGINT gracefully
    ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
    defer stop()

    // Set up OTel SDK
    otelShutdown, err := setupOTelSDK(ctx)
    if err != nil {
        log.Fatal(err)
    }
    defer func() {
        if err := otelShutdown(context.Background()); err != nil {
            log.Printf("Error shutting down OTel SDK: %v", err)
        }
    }()

    // HTTP server with OTel instrumentation
    mux := http.NewServeMux()
    mux.HandleFunc("/rolldice/", rollDice)

    handler := otelhttp.NewHandler(mux, "/")
    srv := &http.Server{Addr: ":8080", Handler: handler}

    // Start server
    go func() {
        if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
            log.Fatalf("listen: %s\n", err)
        }
    }()

    // Wait for interrupt signal
    <-ctx.Done()
    stop()
    log.Println("Shutting down server...")

    shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
    defer cancel()
    if err := srv.Shutdown(shutdownCtx); err != nil {
        log.Printf("Server shutdown error: %v", err)
    }
}
```

### Manual Span Creation

```go
import (
    "go.opentelemetry.io/otel"
    "go.opentelemetry.io/otel/attribute"
)

var tracer = otel.Tracer("myapp/component")

func myFunction(ctx context.Context, userID string) error {
    ctx, span := tracer.Start(ctx, "myFunction",
        trace.WithAttributes(
            attribute.String("user.id", userID),
        ),
    )
    defer span.End()

    // ... do work ...

    if err != nil {
        span.RecordError(err)
        span.SetStatus(codes.Error, err.Error())
        return err
    }
    return nil
}
```

### HTTP Route Tag for Better Span Names

```go
import "go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"

mux.Handle("/users/{id}",
    otelhttp.WithRouteTag("/users/{id}", http.HandlerFunc(handleUser)),
)
```

### Run with Environment Variables

```bash
# Against local Alloy
OTEL_RESOURCE_ATTRIBUTES="service.name=myapp,service.namespace=myteam,deployment.environment=prod" \
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317 \
OTEL_EXPORTER_OTLP_PROTOCOL=grpc \
go run .

# Direct to Grafana Cloud
OTEL_RESOURCE_ATTRIBUTES="service.name=myapp,service.namespace=myteam,deployment.environment=prod" \
OTEL_EXPORTER_OTLP_ENDPOINT=https://otlp-gateway-prod-us-east-0.grafana.net/otlp \
OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf \
OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic $(echo -n '123456:glc_eyJ...' | base64)" \
go run .
```

---

## Java (Grafana Distribution)

### Requirements
- JDK 8+
- Download JAR from https://github.com/grafana/grafana-opentelemetry-java/releases

### Zero-Code Instrumentation (JVM Agent)

No code changes required - the agent auto-instruments popular frameworks (Spring, Quarkus, etc.):

```bash
OTEL_RESOURCE_ATTRIBUTES="service.name=shoppingcart,service.namespace=ecommerce,deployment.environment=production" \
OTEL_EXPORTER_OTLP_ENDPOINT=https://otlp-gateway-prod-us-east-0.grafana.net/otlp \
OTEL_EXPORTER_OTLP_PROTOCOL="http/protobuf" \
OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic $(echo -n '123456:glc_eyJ...' | base64)" \
java -javaagent:/opt/grafana-opentelemetry-java.jar -jar myapp.jar
```

### Configuration Options

```bash
# Enable Application Observability optimized metrics (reduces cost)
export GRAFANA_OTEL_APPLICATION_OBSERVABILITY_METRICS=true

# Debug mode
export OTEL_JAVAAGENT_DEBUG=true

# Console output for debugging (alongside OTLP)
export OTEL_TRACES_EXPORTER=otlp,console
export OTEL_METRICS_EXPORTER=otlp,console
export OTEL_LOGS_EXPORTER=otlp,console

# Disable agent entirely (for testing)
export OTEL_JAVAAGENT_ENABLED=false
```

### Upstream OTel SDK Migration

If migrating from Grafana Java agent to upstream OTel SDK, add:

```bash
export OTEL_INSTRUMENTATION_MICROMETER_BASE_TIME_UNIT=s
export OTEL_INSTRUMENTATION_LOG4J_APPENDER_EXPERIMENTAL_LOG_ATTRIBUTES=true
export OTEL_INSTRUMENTATION_LOGBACK_APPENDER_EXPERIMENTAL_LOG_ATTRIBUTES=true
```

### Spring Boot Example (manual spans)

```java
import io.opentelemetry.api.GlobalOpenTelemetry;
import io.opentelemetry.api.trace.Span;
import io.opentelemetry.api.trace.Tracer;

@Service
public class OrderService {
    private final Tracer tracer = GlobalOpenTelemetry.getTracer("order-service");

    public Order processOrder(String orderId) {
        Span span = tracer.spanBuilder("processOrder")
            .setAttribute("order.id", orderId)
            .startSpan();
        try (var scope = span.makeCurrent()) {
            // ... do work ...
            return order;
        } catch (Exception e) {
            span.recordException(e);
            throw e;
        } finally {
            span.end();
        }
    }
}
```

---

## Node.js

### Zero-Config Auto-Instrumentation

```bash
npm install --save @opentelemetry/api @opentelemetry/auto-instrumentations-node
```

```bash
OTEL_TRACES_EXPORTER="otlp" \
OTEL_METRICS_EXPORTER="otlp" \
OTEL_LOGS_EXPORTER="otlp" \
OTEL_NODE_RESOURCE_DETECTORS="env,host,os" \
OTEL_RESOURCE_ATTRIBUTES="service.name=myapp,service.namespace=myteam,deployment.environment=prod" \
OTEL_EXPORTER_OTLP_ENDPOINT=https://otlp-gateway-prod-us-east-0.grafana.net/otlp \
OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic $(echo -n '123456:glc_eyJ...' | base64)" \
NODE_OPTIONS="--require @opentelemetry/auto-instrumentations-node/register" \
node app.js
```

### Manual SDK Setup (TypeScript/ESM)

```bash
npm install --save \
  @opentelemetry/api \
  @opentelemetry/sdk-node \
  @opentelemetry/exporter-trace-otlp-http \
  @opentelemetry/exporter-metrics-otlp-http \
  @opentelemetry/resources \
  @opentelemetry/semantic-conventions \
  @opentelemetry/auto-instrumentations-node
```

```typescript
// instrumentation.ts
import { NodeSDK } from '@opentelemetry/sdk-node';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-http';
import { OTLPMetricExporter } from '@opentelemetry/exporter-metrics-otlp-http';
import { PeriodicExportingMetricReader } from '@opentelemetry/sdk-metrics';
import { Resource } from '@opentelemetry/resources';
import { ATTR_SERVICE_NAME, ATTR_SERVICE_VERSION } from '@opentelemetry/semantic-conventions';
import { getNodeAutoInstrumentations } from '@opentelemetry/auto-instrumentations-node';

const sdk = new NodeSDK({
  resource: new Resource({
    [ATTR_SERVICE_NAME]: 'myapp',
    [ATTR_SERVICE_VERSION]: '1.0.0',
  }),
  traceExporter: new OTLPTraceExporter({
    url: process.env.OTEL_EXPORTER_OTLP_ENDPOINT + '/v1/traces',
    headers: {
      Authorization: `Basic ${Buffer.from(
        `${process.env.GRAFANA_INSTANCE_ID}:${process.env.GRAFANA_API_KEY}`
      ).toString('base64')}`,
    },
  }),
  metricReader: new PeriodicExportingMetricReader({
    exporter: new OTLPMetricExporter({
      url: process.env.OTEL_EXPORTER_OTLP_ENDPOINT + '/v1/metrics',
    }),
  }),
  instrumentations: [getNodeAutoInstrumentations()],
});

sdk.start();
process.on('SIGTERM', () => {
  sdk.shutdown().finally(() => process.exit(0));
});
```

```typescript
// Load BEFORE your app code in package.json or CLI:
// node --require ./instrumentation.js app.js
```

### Manual Span Creation (Node.js)

```typescript
import { trace, context } from '@opentelemetry/api';

const tracer = trace.getTracer('myapp');

async function handleRequest(req: Request) {
  const span = tracer.startSpan('handleRequest', {
    attributes: {
      'http.method': req.method,
      'user.id': req.userId,
    },
  });

  return context.with(trace.setSpan(context.active(), span), async () => {
    try {
      const result = await processRequest(req);
      return result;
    } catch (err) {
      span.recordException(err as Error);
      throw err;
    } finally {
      span.end();
    }
  });
}
```

---

## Python

### Zero-Code Auto-Instrumentation

```bash
pip install "opentelemetry-distro[otlp]"
opentelemetry-bootstrap -a install   # installs framework-specific instrumentors
```

```bash
OTEL_RESOURCE_ATTRIBUTES="service.name=myapp,service.namespace=myteam,deployment.environment=prod" \
OTEL_EXPORTER_OTLP_ENDPOINT=https://otlp-gateway-prod-us-east-0.grafana.net/otlp \
OTEL_EXPORTER_OTLP_PROTOCOL="http/protobuf" \
OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic $(echo -n '123456:glc_eyJ...' | base64)" \
opentelemetry-instrument python app.py
```

### Manual SDK Setup

```bash
pip install \
  opentelemetry-api \
  opentelemetry-sdk \
  opentelemetry-exporter-otlp-proto-http
```

```python
# otel_setup.py
import os
from opentelemetry import trace, metrics
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.exporter.otlp.proto.http.metric_exporter import OTLPMetricExporter
from opentelemetry.sdk.resources import Resource

def setup_otel():
    resource = Resource.create({
        "service.name": os.getenv("OTEL_SERVICE_NAME", "myapp"),
        "service.namespace": "myteam",
        "deployment.environment": "production",
    })

    endpoint = os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT", "http://localhost:4318")
    headers = {}
    if os.getenv("OTEL_EXPORTER_OTLP_HEADERS"):
        for header in os.getenv("OTEL_EXPORTER_OTLP_HEADERS").split(","):
            k, v = header.split("=", 1)
            headers[k.strip()] = v.strip()

    # Traces
    trace_exporter = OTLPSpanExporter(
        endpoint=f"{endpoint}/v1/traces",
        headers=headers,
    )
    tracer_provider = TracerProvider(resource=resource)
    tracer_provider.add_span_processor(BatchSpanProcessor(trace_exporter))
    trace.set_tracer_provider(tracer_provider)

    # Metrics
    metric_exporter = OTLPMetricExporter(
        endpoint=f"{endpoint}/v1/metrics",
        headers=headers,
    )
    meter_provider = MeterProvider(
        resource=resource,
        metric_readers=[PeriodicExportingMetricReader(metric_exporter)],
    )
    metrics.set_meter_provider(meter_provider)

    return tracer_provider, meter_provider
```

### Manual Spans (Python)

```python
from opentelemetry import trace

tracer = trace.get_tracer("myapp.component")

def process_order(order_id: str):
    with tracer.start_as_current_span("process_order") as span:
        span.set_attribute("order.id", order_id)
        try:
            result = do_processing(order_id)
            return result
        except Exception as e:
            span.record_exception(e)
            span.set_status(trace.StatusCode.ERROR, str(e))
            raise
```

### Gunicorn Post-Fork Hook (multi-process)

```python
# gunicorn.conf.py
from opentelemetry.instrumentation.gunicorn import GunicornInstrumentor

def post_fork(server, worker):
    GunicornInstrumentor().instrument_app(worker.app.wsgi())
    # Or manually reinitialize providers here
```

---

## .NET (Grafana Distribution)

### Requirements
- .NET 6+ or .NET Framework 4.6.2+

### Install

```bash
dotnet add package Grafana.OpenTelemetry
# For testing with console exporter:
dotnet add package OpenTelemetry.Exporter.Console
```

### ASP.NET Core (.NET 6+)

```csharp
using Grafana.OpenTelemetry;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddOpenTelemetry()
    .WithTracing(tracing =>
    {
        tracing.UseGrafana();
        // Add console for debugging only - remove in production
        // tracing.AddConsoleExporter();
    })
    .WithMetrics(metrics =>
    {
        metrics.UseGrafana();
    });

builder.Logging.AddOpenTelemetry(logging =>
{
    logging.UseGrafana();
});

var app = builder.Build();
// ... configure routes ...
app.Run();
```

### Console App (.NET 6+)

```csharp
using OpenTelemetry;
using OpenTelemetry.Metrics;
using OpenTelemetry.Trace;
using Grafana.OpenTelemetry;

using var tracerProvider = Sdk.CreateTracerProviderBuilder()
    .UseGrafana()
    .Build();

using var meterProvider = Sdk.CreateMeterProviderBuilder()
    .UseGrafana()
    .Build();

using var loggerFactory = LoggerFactory.Create(builder =>
{
    builder.AddOpenTelemetry(logging =>
    {
        logging.UseGrafana();
    });
});

// Your app code here
```

### .NET Framework (4.6.2+)

```csharp
using Grafana.OpenTelemetry;
using OpenTelemetry;
using OpenTelemetry.Metrics;
using OpenTelemetry.Trace;

public class WebApiApplication : System.Web.HttpApplication
{
    private TracerProvider _tracerProvider;
    private MeterProvider _meterProvider;

    protected void Application_Start()
    {
        _tracerProvider = Sdk.CreateTracerProviderBuilder()
            .UseGrafana()
            .Build();

        _meterProvider = Sdk.CreateMeterProviderBuilder()
            .UseGrafana()
            .Build();
    }

    protected void Application_End()
    {
        _tracerProvider?.Dispose();
        _meterProvider?.Dispose();
    }
}
```

### Manual Span Creation (.NET)

```csharp
using System.Diagnostics;

public class OrderService
{
    private static readonly ActivitySource ActivitySource = new("MyApp.OrderService");

    public async Task<Order> ProcessOrderAsync(string orderId)
    {
        using var activity = ActivitySource.StartActivity("ProcessOrder");
        activity?.SetTag("order.id", orderId);

        try
        {
            var order = await DoProcessingAsync(orderId);
            activity?.SetStatus(ActivityStatusCode.Ok);
            return order;
        }
        catch (Exception ex)
        {
            activity?.SetStatus(ActivityStatusCode.Error, ex.Message);
            activity?.RecordException(ex);
            throw;
        }
    }
}
```

### Run with Environment Variables

```bash
OTEL_RESOURCE_ATTRIBUTES="service.name=myapp,service.namespace=myteam,deployment.environment=prod" \
OTEL_EXPORTER_OTLP_ENDPOINT=https://otlp-gateway-prod-us-east-0.grafana.net/otlp \
OTEL_EXPORTER_OTLP_PROTOCOL="http/protobuf" \
OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic $(echo -n '123456:glc_eyJ...' | base64)" \
dotnet run
```

---

## PHP

### Install

```bash
composer require open-telemetry/opentelemetry-auto-slim \
  open-telemetry/exporter-otlp \
  php-http/guzzle7-adapter
```

### Setup

```php
<?php
// otel.php - loaded via auto_prepend_file or require
use OpenTelemetry\API\Globals;
use OpenTelemetry\Contrib\Otlp\OtlpHttpExporterFactory;
use OpenTelemetry\SDK\Trace\TracerProviderFactory;

$exporter = (new OtlpHttpExporterFactory())->create();
$tracerProvider = (new TracerProviderFactory())->create(null, null, $exporter);
Globals::registerInitializer(function (Configurator $configurator) use ($tracerProvider) {
    return $configurator->withTracerProvider($tracerProvider);
});
```

### Environment Variables

```bash
OTEL_PHP_AUTOLOAD_ENABLED=true \
OTEL_SERVICE_NAME=myapp \
OTEL_EXPORTER_OTLP_ENDPOINT=https://otlp-gateway-prod-us-east-0.grafana.net/otlp \
OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic $(echo -n '123456:glc_eyJ...' | base64)" \
php app.php
```

---

## Grafana Beyla (eBPF Auto-Instrumentation)

Works with any language - instruments at network level without code changes.

### Docker

```bash
docker run --rm -it \
  --privileged \
  --network host \
  -e BEYLA_SERVICE_NAME=myapp \
  -e OTEL_EXPORTER_OTLP_ENDPOINT=http://alloy:4317 \
  -e BEYLA_OPEN_PORT=8080 \
  -v /sys/kernel/security:/sys/kernel/security \
  -v /sys/fs/cgroup:/sys/fs/cgroup \
  grafana/beyla:latest
```

### Kubernetes (DaemonSet)

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: beyla
spec:
  selector:
    matchLabels:
      app: beyla
  template:
    metadata:
      labels:
        app: beyla
    spec:
      hostPID: true
      containers:
      - name: beyla
        image: grafana/beyla:latest
        securityContext:
          privileged: true
        env:
        - name: BEYLA_SERVICE_NAME
          value: "auto"
        - name: OTEL_EXPORTER_OTLP_ENDPOINT
          value: "http://alloy.monitoring:4317"
        - name: BEYLA_KUBE_METADATA_ENABLE
          value: "true"
        volumeMounts:
        - name: sys-kernel-security
          mountPath: /sys/kernel/security
      volumes:
      - name: sys-kernel-security
        hostPath:
          path: /sys/kernel/security
```

### Verify

```bash
curl http://localhost:9090/metrics | grep beyla_build_info
```

---

## Common Patterns

### Generate Basic Auth Header

```bash
# Bash
echo -n "INSTANCE_ID:API_TOKEN" | base64

# Result example: MTIzNDU2OmdsY19leUo...
```

### Resource Attributes Best Practices

Always set these three attributes:

```bash
OTEL_RESOURCE_ATTRIBUTES="service.name=<name>,service.namespace=<namespace>,deployment.environment=<env>"
```

- `service.name`: Unique name for the service (e.g. `payment-api`, `frontend`)
- `service.namespace`: Groups related services (e.g. `checkout`, `platform`)
- `deployment.environment`: Environment tier (`production`, `staging`, `development`)

### Protocol Selection

| Use Case | Protocol | Port |
|----------|----------|------|
| Best performance | `grpc` | 4317 |
| HTTP-only environments | `http/protobuf` | 4318 |
| Grafana Cloud direct | `http/protobuf` | 443 (HTTPS) |

### Debug: Verify Telemetry is Flowing

```bash
# Stdout exporter for traces
OTEL_TRACES_EXPORTER=console go run .

# For Java
OTEL_TRACES_EXPORTER=otlp,console java -javaagent:agent.jar -jar app.jar

# Check connectivity
curl -v https://otlp-gateway-prod-us-east-0.grafana.net/otlp/v1/traces \
  -H "Authorization: Basic <base64>" \
  -H "Content-Type: application/x-protobuf" \
  --data-binary @empty.bin
```
