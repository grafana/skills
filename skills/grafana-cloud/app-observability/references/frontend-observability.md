# Grafana Frontend Observability - Faro SDK Reference

## What is Faro?

Grafana Faro is an open-source JavaScript/TypeScript SDK for Real User Monitoring (RUM). It instruments browser frontend applications to capture observability signals and correlate them with backend telemetry.

GitHub: https://github.com/grafana/faro-web-sdk
Docs: https://grafana.com/docs/grafana-cloud/monitor-applications/frontend-observability/

## Package Structure

| Package | Purpose |
|---|---|
| `@grafana/faro-core` | Core SDK foundation: signals, transports, API surface |
| `@grafana/faro-web-sdk` | Web instrumentations, web vitals, fetch/XHR, transports |
| `@grafana/faro-web-tracing` | OpenTelemetry-JS distributed tracing for browsers |
| `@grafana/faro-react` | React error boundary, router integration, component profiler |

## Installation

### NPM / Yarn

```bash
# Core SDK only
npm install @grafana/faro-web-sdk

# With distributed tracing
npm install @grafana/faro-web-sdk @grafana/faro-web-tracing

# With React integration
npm install @grafana/faro-web-sdk @grafana/faro-web-tracing @grafana/faro-react
```

### CDN (no bundler)

The library is distributed as IIFE and exposes a global `GrafanaFaroWebSdk`:

```html
<!-- Web SDK -->
<script src="https://unpkg.com/@grafana/faro-web-sdk@latest/dist/library/faro-web-sdk.iife.js"></script>

<!-- Web Tracing (optional) -->
<script src="https://unpkg.com/@grafana/faro-web-tracing@latest/dist/library/faro-web-tracing.iife.js"></script>

<script>
  const { initializeFaro, getWebInstrumentations } = GrafanaFaroWebSdk;
  const { TracingInstrumentation } = GrafanaFaroWebTracing;

  initializeFaro({
    url: 'https://faro-collector-prod-<region>.grafana.net/collect/<app-key>',
    app: { name: 'my-app', version: '1.0.0' },
    instrumentations: [
      ...getWebInstrumentations(),
      new TracingInstrumentation(),
    ],
  });
</script>
```

## Core Configuration - `initializeFaro()`

```typescript
interface FaroConfig {
  // Required: Collector endpoint URL from Grafana Cloud Frontend Observability
  url: string;

  // Application metadata
  app: {
    name: string;           // Required - identifies your app
    version?: string;       // Recommended - for release tracking
    environment?: string;   // e.g. 'production', 'staging'
    namespace?: string;     // Optional grouping
  };

  // Instrumentations to enable
  instrumentations?: Instrumentation[];

  // Session tracking options
  sessionTracking?: {
    enabled?: boolean;                  // default: true
    persistent?: boolean;               // survives tab close; default: false
    maxSessionPersistenceTime?: number; // ms; default: 4 hours
    samplingRate?: number;              // 0-1; default: 1 (100%)
    generateSessionId?: () => string;   // custom ID generator
    onSessionChange?: (oldSession: Session | null, newSession: Session) => void;
  };

  // Optional: override or add metadata
  user?: {
    id?: string;
    username?: string;
    email?: string;
    attributes?: Record<string, string>;
  };

  // Optional: global attributes added to all signals
  globalObjectKey?: string; // window key; default: '__faroBridge'

  // Batch send options
  batchSendCount?: number;   // signals per batch; default: 50
  batchSendTimeout?: number; // ms before forced flush; default: 250
}
```

## Minimal Setup

```javascript
import { initializeFaro, getWebInstrumentations } from '@grafana/faro-web-sdk';

initializeFaro({
  url: 'https://faro-collector-prod-us-east-0.grafana.net/collect/abc123',
  app: {
    name: 'my-app',
    version: '1.0.0',
    environment: 'production',
  },
  instrumentations: [...getWebInstrumentations()],
});
```

## `getWebInstrumentations()` Options

```javascript
getWebInstrumentations({
  // Capture console.log, console.warn, console.error as Faro logs
  captureConsole: true,           // default: false
  captureConsoleDisabledLevels: ['log'], // exclude certain levels

  // Capture page visibility changes
  capturePageVisibility: true,    // default: true
})
```

What's automatically included in `getWebInstrumentations()`:
- `PerformanceInstrumentation` - navigation timing, resource loading, web vitals
- `ErrorsInstrumentation` - unhandled errors and promise rejections
- `ConsoleInstrumentation` - console capture (if `captureConsole: true`)
- `SessionInstrumentation` - session lifecycle tracking
- `ViewInstrumentation` - page view tracking

## Web Vitals Captured

Faro v2 uses Web Vitals v5:
- **LCP** (Largest Contentful Paint) - loading performance
- **CLS** (Cumulative Layout Shift) - visual stability
- **INP** (Interaction to Next Paint) - interactivity (replaces FID)
- **FCP** (First Contentful Paint)
- **TTFB** (Time to First Byte)

## Manual API Usage

```javascript
const faro = initializeFaro({ ... });

// Push a log message
faro.api.pushLog(['User completed checkout'], {
  level: LogLevel.INFO,
  context: { orderId: '12345' },
});

// Push an error manually
faro.api.pushError(new Error('Payment gateway timeout'), {
  type: 'NetworkError',
  context: { endpoint: '/api/pay' },
});

// Push a custom event
faro.api.pushEvent('feature_used', {
  feature: 'dark_mode',
  source: 'settings_page',
});

// Push a measurement (custom metric)
faro.api.pushMeasurement({
  type: 'custom_timing',
  values: {
    checkout_duration_ms: 1234,
  },
});

// Set user context
faro.api.setUser({
  id: 'user-456',
  username: 'jane.doe',
  attributes: { plan: 'premium' },
});

// Set custom global attributes
faro.api.setSession({ attributes: { experiment: 'checkout-v2' } });
```

## Distributed Tracing Setup

Adds OpenTelemetry browser tracing to correlate frontend spans with backend traces.

```javascript
import { initializeFaro, getWebInstrumentations } from '@grafana/faro-web-sdk';
import { TracingInstrumentation } from '@grafana/faro-web-tracing';

initializeFaro({
  url: '...',
  app: { name: 'my-app' },
  instrumentations: [
    ...getWebInstrumentations(),
    new TracingInstrumentation({
      // Propagate trace context to these URLs (supports regex)
      propagateTraceHeaderCorsUrls: [
        /https:\/\/api\.myapp\.com\/.*/,
        'https://internal.service.com',
      ],
      // Custom sampling rate for traces (0-1)
      // samplingRate: 0.5,
    }),
  ],
});
```

When enabled:
- `traceparent` and `tracestate` headers are injected into all matching fetch/XHR requests
- Browser creates spans for each HTTP call
- Traces appear in Grafana Tempo correlated to backend spans
- Session ID is propagated as a baggage item

## React Integration

### React Router v6 (data router API - recommended)

```javascript
import { initializeFaro, getWebInstrumentations } from '@grafana/faro-web-sdk';
import { TracingInstrumentation } from '@grafana/faro-web-tracing';
import {
  createReactRouterV6DataOptions,
  ReactIntegration,
  withFaroRouterInstrumentation,
} from '@grafana/faro-react';
import { createBrowserRouter, RouterProvider } from 'react-router-dom';

// Must call BEFORE rendering
initializeFaro({
  url: 'https://faro-collector-prod-<region>.grafana.net/collect/<key>',
  app: { name: 'my-react-app', version: '2.0.0', environment: 'production' },
  instrumentations: [
    ...getWebInstrumentations({ captureConsole: true }),
    new TracingInstrumentation(),
    new ReactIntegration({
      router: createReactRouterV6DataOptions({}),
    }),
  ],
});

// Instrument the router
const router = withFaroRouterInstrumentation(
  createBrowserRouter([
    { path: '/', element: <HomePage /> },
    { path: '/products/:id', element: <ProductPage /> },
    { path: '/checkout', element: <CheckoutPage /> },
  ])
);

function App() {
  return <RouterProvider router={router} />;
}
```

### React Router v6 (non-data router - Routes component)

```javascript
import {
  createReactRouterV6Options,
  ReactIntegration,
  FaroRoutes,
} from '@grafana/faro-react';
import { useLocation, useNavigationType, createRoutesFromChildren, matchRoutes } from 'react-router-dom';

initializeFaro({
  // ...
  instrumentations: [
    ...getWebInstrumentations(),
    new TracingInstrumentation(),
    new ReactIntegration({
      router: createReactRouterV6Options({
        useLocation,
        useNavigationType,
        createRoutesFromChildren,
        matchRoutes,
      }),
    }),
  ],
});

// In your component tree, use FaroRoutes instead of Routes:
function AppRoutes() {
  return (
    <FaroRoutes>
      <Route path="/" element={<HomePage />} />
      <Route path="/about" element={<AboutPage />} />
    </FaroRoutes>
  );
}
```

### React Router v4/v5

```javascript
import {
  createReactRouterV5Options,
  ReactIntegration,
} from '@grafana/faro-react';
import { createBrowserHistory } from 'history';
import { Router } from 'react-router-dom';

const history = createBrowserHistory();

initializeFaro({
  // ...
  instrumentations: [
    ...getWebInstrumentations(),
    new TracingInstrumentation(),
    new ReactIntegration({
      router: createReactRouterV5Options({ history }),
    }),
  ],
});

// Wrap app with Router using the same history instance
function App() {
  return (
    <Router history={history}>
      <YourRoutes />
    </Router>
  );
}
```

### React Error Boundary

```javascript
import { FaroErrorBoundary, withErrorBoundary } from '@grafana/faro-react';

// As a component
function App() {
  return (
    <FaroErrorBoundary
      fallback={<ErrorFallback />}
      pushErrorAsFaro={true}       // auto-pushes to Faro (default: true)
    >
      <MainContent />
    </FaroErrorBoundary>
  );
}

// As a HOC
const SafeComponent = withErrorBoundary(MyComponent, {
  fallback: <p>Something went wrong</p>,
});
```

## Session Tracking Details

```javascript
import {
  initializeFaro,
  getWebInstrumentations,
  SessionInstrumentation,
} from '@grafana/faro-web-sdk';

initializeFaro({
  url: '...',
  app: { name: 'my-app' },
  sessionTracking: {
    enabled: true,

    // Persist session across browser restarts (uses localStorage)
    persistent: true,

    // Max time a persistent session lives (milliseconds)
    // Default: 4 hours
    maxSessionPersistenceTime: 4 * 60 * 60 * 1000,

    // Sample only 50% of sessions to reduce data volume
    samplingRate: 0.5,

    // Custom session ID (useful for server-side session correlation)
    generateSessionId: () => crypto.randomUUID(),

    // Hook for analytics or logging on session rotation
    onSessionChange: (oldSession, newSession) => {
      console.log(`New session: ${newSession.id}`);
      analytics.track('session_started', { id: newSession.id });
    },
  },
  instrumentations: [...getWebInstrumentations()],
});
```

## Session Replay

Session Replay records DOM mutations using rrweb, allowing visual playback of user sessions.

Setup steps:
1. In Grafana Cloud > Connections > Frontend Observability > Web SDK Configuration
2. Enable "Session Replay" toggle to get a replay-enabled collector URL
3. Install the SDK - the collector key controls what's recorded server-side

The basic `initializeFaro` setup works - session replay is controlled by the collector URL/key:

```javascript
initializeFaro({
  // Use the replay-enabled collector URL from Grafana Cloud UI
  url: 'https://faro-collector-prod-<region>.grafana.net/collect/<replay-enabled-key>',
  app: { name: 'my-app', version: '1.0.0' },
  instrumentations: [...getWebInstrumentations()],
  sessionTracking: {
    persistent: true,
    samplingRate: 0.1, // Record 10% of sessions for replay (cost control)
  },
});
```

In Grafana Cloud Frontend Observability:
- Sessions panel shows timeline of user actions
- "Play" button on any session opens the replay viewer
- Filters: by error, by duration, by user, by URL

## Getting Collector URL

The collector URL is unique per application and environment:

1. Navigate to Grafana Cloud stack
2. Left menu: **Connections** > search "Frontend Observability"
3. Click the Frontend Observability tile
4. Click **Web SDK Configuration** tab
5. Copy the `url` field shown (format: `https://faro-collector-prod-<region>.grafana.net/collect/<app-key>`)

The same page shows:
- Your App Name (pre-configured)
- Sample rate settings
- Replay toggle
- CDN script tags for quick integration

## Fetch Instrumentation Customization

Control which requests are traced and what headers are captured:

```javascript
import { FetchInstrumentation } from '@grafana/faro-web-sdk';

initializeFaro({
  // ...
  instrumentations: [
    new FetchInstrumentation({
      // Capture specific request headers
      requestHeaders: ['x-request-id', 'x-correlation-id'],
      // Capture specific response headers
      responseHeaders: ['x-trace-id'],
      // Ignore certain URLs from tracking
      ignoredUrls: [/.*\/health/, 'https://analytics.internal/'],
    }),
  ],
});
```

## Data Flow Architecture

```
Browser App
    |
    | (HTTP POST, batched)
    v
Faro Collector (Grafana Cloud)
    |
    |-- Logs -------> Grafana Loki
    |-- Traces -----> Grafana Tempo
    |-- Metrics ----> Grafana Mimir
    |
Visualized in Grafana Cloud Frontend Observability dashboards
```

Alternative with self-hosted Alloy:
```
Browser App --> Grafana Alloy (faro.receiver) --> Grafana Cloud backends
```

## Alloy Configuration (self-hosted)

If routing through your own Alloy instance:

```river
faro.receiver "default" {
  server {
    listen_address           = "0.0.0.0"
    listen_port              = 12347
    cors_allowed_origins     = ["https://myapp.com"]
    api_key                  = env("FARO_API_KEY")
    max_allowed_payload_size = "10MiB"
  }

  sourcemaps {
    download          = true
    upload {
      external_url = "https://myfrontend.cdn.com"
    }
  }

  output {
    logs   = [loki.write.grafana_cloud.receiver]
    traces = [otelcol.exporter.otlphttp.grafana_cloud.input]
  }
}
```

## Correlation with Backend

Frontend-to-backend trace correlation requires:

1. Faro has `TracingInstrumentation` enabled
2. Backend accepts W3C `traceparent` headers
3. Both frontend and backend send to the same Grafana Cloud Tempo instance

In Tempo trace view, the root span will show `session.id` attribute linking to the Faro session.

In Frontend Observability, errors show "View trace" button when a `traceId` is present.

## Upgrading to Faro v2

Faro v2 changes from v1:
- **Web Vitals v5**: FID removed, INP added as Core Web Vital
- **Console instrumentation**: Simplified - `captureConsole` is now an option in `getWebInstrumentations()`
- **Tracing APIs**: Some deprecated span attributes removed
- **Session attributes**: New structured approach

Migration: https://grafana.com/docs/grafana-cloud/monitor-applications/frontend-observability/instrument/upgrading/upgrade-v2/

## Prebuilt Dashboards in Grafana Cloud

Frontend Observability auto-provisions:
- **Overview** - session count, error rate, web vitals scores
- **Sessions** - session list with replay links
- **Errors** - error grouping, stack traces, affected sessions
- **Performance** - web vitals trends, resource loading, navigation timing
- **User Journey** - page flow, drop-off points
