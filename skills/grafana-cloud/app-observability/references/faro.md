# Frontend Observability (Faro)

## SDK packages

```
@grafana/faro-core          # core API + transports
@grafana/faro-web-sdk       # web instrumentations + transports
@grafana/faro-web-tracing   # OpenTelemetry-JS distributed tracing
@grafana/faro-react         # React error boundary + router integration
```

## Basic web setup (npm)

```bash
npm install @grafana/faro-web-sdk
```

```javascript
import { initializeFaro, getWebInstrumentations } from '@grafana/faro-web-sdk';

const faro = initializeFaro({
  url: 'https://faro-collector-prod-<region>.grafana.net/collect/<app-key>',
  app: { name: 'my-frontend-app', version: '1.0.0', environment: 'production' },
  instrumentations: [
    ...getWebInstrumentations({ captureConsole: true }),
  ],
});

faro.api.pushLog(['User clicked checkout']);
faro.api.pushError(new Error('Payment failed'));
faro.api.pushEvent('button_click', { button: 'checkout' });
```

## CDN setup

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

## React + tracing

```bash
npm install @grafana/faro-react @grafana/faro-web-tracing
```

```javascript
import { initializeFaro, getWebInstrumentations } from '@grafana/faro-web-sdk';
import { TracingInstrumentation }               from '@grafana/faro-web-tracing';
import { createReactRouterV6DataOptions, ReactIntegration,
         withFaroRouterInstrumentation }        from '@grafana/faro-react';
import { createBrowserRouter, RouterProvider }  from 'react-router-dom';

initializeFaro({
  url: 'https://faro-collector-prod-<region>.grafana.net/collect/<app-key>',
  app: { name: 'my-react-app', version: '1.0.0', environment: 'production' },
  instrumentations: [
    ...getWebInstrumentations({ captureConsole: true }),
    new TracingInstrumentation(),
    new ReactIntegration({ router: createReactRouterV6DataOptions({}) }),
  ],
});

const router = withFaroRouterInstrumentation(createBrowserRouter([
  { path: '/',      element: <Home />  },
  { path: '/about', element: <About /> },
]));
```

## Session config

```javascript
initializeFaro({
  url: '...', app: { name: 'my-app' },
  sessionTracking: {
    enabled: true,
    persistent: true,
    maxSessionPersistenceTime: 4 * 60 * 60 * 1000, // 4 hours
    samplingRate: 1,  // 1 = 100%
    onSessionChange: (oldS, newS) => console.log('session', newS.id),
  },
  instrumentations: [...getWebInstrumentations()],
});
```

## Where to find the collector URL

Grafana Cloud → **Connections** → search "Frontend Observability" → click → **Web SDK Configuration** tab → copy the `url`.

## Auto-captured signals

- Page views + navigation timing
- Core Web Vitals (LCP, CLS, INP — INP replaces FID in Faro v2)
- JS errors + unhandled rejections
- Console errors / warnings (when `captureConsole: true`)
- Resource loading performance
- User interactions (clicks, form events)
- Fetch / XHR timing
- With `TracingInstrumentation`: `traceparent` header injection → backend trace correlation
