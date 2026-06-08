# Test types

Six test types, one file per type, all hybrid except breakpoint.

| Type        | Purpose                                | Executor             | Default ramp                |
|-------------|----------------------------------------|----------------------|------------------------------|
| smoke       | sanity check the script + thresholds   | constant-vus         | 3 VUs × 1m                   |
| average     | expected production load               | ramping-vus          | 0→20→0 over 14m              |
| stress      | beyond expected, find the cliff        | ramping-vus          | 0→50→0 over 20m              |
| spike       | sudden VU jump, check recovery         | ramping-vus          | 0→100→0 over 2m              |
| soak        | sustained load, find leaks / drift     | ramping-vus          | 0→10→0 over 70m              |
| breakpoint  | ramping arrival rate, find the ceiling | ramping-arrival-rate | 5/s→500/s over 20m, abortOnFail |

Defaults are starting points. Always tune after smoke.

## smoke

Goal: confirm the script behaves correctly under production-like
but trivially small load. **Always run before any other test
type.** If smoke fails, fix the script before scaling.

```js
scenarios: {
  protocol: {
    executor: 'constant-vus',
    exec: 'protocolIteration',
    vus: 3, duration: '1m',
  },
  browser: { executor: 'constant-vus', vus: 1, duration: '1m',
             exec: 'browserIteration',
             options: { browser: { type: 'chromium' } } },
},
thresholds: { /* full SLO + per-endpoint + iteration + web vitals */ },
```

A passing smoke means: thresholds compile, the script doesn't error,
all assertions hold at low load. **Smoke is not a measurement.**

## average

Expected production load. Tune `target` VUs to match the customer's
typical concurrent user count.

```js
protocol: {
  executor: 'ramping-vus',
  exec: 'protocolIteration',
  startVUs: 0,
  stages: [
    { duration: '2m',  target: 20 },   // ramp up
    { duration: '10m', target: 20 },   // hold
    { duration: '2m',  target: 0  },   // ramp down
  ],
},
browser: { /* constant 1 VU for the full 14m */ },
```

Pass criteria: every SLO threshold holds.

## stress

Beyond expected load. Goal: find where SLOs start to break.

```js
protocol: {
  executor: 'ramping-vus',
  exec: 'protocolIteration',
  startVUs: 0,
  stages: [
    { duration: '5m',  target: 50 },
    { duration: '10m', target: 50 },
    { duration: '5m',  target: 0  },
  ],
},
```

Expected outcome: some thresholds fail. The **specific** thresholds
that fail tell you which part of the system is the bottleneck.
Report each failure with its tag (which endpoint), peak VU count,
and timestamp.

## spike

Sudden jump in VUs; goal is to verify the system recovers.

```js
protocol: {
  executor: 'ramping-vus',
  exec: 'protocolIteration',
  startVUs: 0,
  stages: [
    { duration: '30s', target: 100 },   // spike
    { duration: '1m',  target: 100 },   // hold at peak
    { duration: '30s', target: 0   },   // drop
  ],
},
```

What to look for:

- During the spike: do `http_req_failed` and latency stay within
  acceptable bounds? (Some degradation is expected.)
- After the drop: does the system return to baseline?
- Cold caches, connection pool warmup, autoscaler latency — all
  surface here.

## soak

Sustained moderate load over a long window. Goal: find memory
leaks, connection drift, scheduled-job interference, cache
eviction patterns.

```js
protocol: {
  executor: 'ramping-vus',
  exec: 'protocolIteration',
  startVUs: 0,
  stages: [
    { duration: '5m',  target: 10 },
    { duration: '60m', target: 10 },
    { duration: '5m',  target: 0  },
  ],
},
```

What to look for:

- Is `iteration_duration` flat, or trending up?
- Is k6's RSS (LG monitor) climbing without bound? See gotchas:
  the climb may be client-side metric accumulation, not a real
  leak. Verify against backend metrics before reporting.
- Are there periodic spikes (cron jobs, GC, log rotations)?

**Soak is the most likely test type to exhaust Grafana Cloud k6
budget.** Confirm with the user before pushing to cloud.

## breakpoint

Find the ceiling. **Protocol-only** (no browser scenario — adds
noise to the signal).

```js
scenarios: {
  protocol: {
    executor: 'ramping-arrival-rate',
    exec: 'protocolIteration',
    startRate: 5,
    timeUnit: '1s',
    preAllocatedVUs: 50,
    maxVUs: 500,
    stages: [{ duration: '20m', target: 500 }],
  },
},
thresholds: {
  http_req_failed:   [{ threshold: 'rate<0.05', abortOnFail: true,
                        delayAbortEval: '30s' }],
  http_req_duration: [{ threshold: 'p(95)<2000', abortOnFail: true,
                        delayAbortEval: '30s' }],
  checks: ['rate>0.95'],
},
```

The `abortOnFail` thresholds stop the run once SLOs break. The
`delayAbortEval` window prevents instantaneous fluctuations from
triggering an abort prematurely.

Read the final iteration rate / arrival rate at the abort point —
that's the breakpoint. Document it in the report.

**Why arrival rate, not VUs:** the cliff is in **requests per
second**, not in concurrent users. VU-based ramps are bounded by
iteration duration; if iterations slow down, VUs back off and you
never reach the cliff. `ramping-arrival-rate` injects requests at
a fixed schedule regardless of iteration speed.

**Two ways the arrival-rate advantage gets silently lost — avoid both:**

- **Think-time sleep in the iteration body.** Every started iteration
  holds a VU until it finishes. A 1-4s `sleep()` (the think-time the
  other test types use) makes each iteration last ~2.5s, so one VU
  serves only ~0.4 iters/s. The breakpoint body must run requests
  back-to-back with **no** think-time. Think-time belongs in
  average/stress/soak, not breakpoint.
- **`maxVUs` set below `target_rate × iteration_seconds`.** When k6
  runs out of VUs it logs `Insufficient VUs, reached N active VUs and
  cannot initialize more` and emits `dropped_iterations`; the achieved
  rate plateaus from VU exhaustion, not from the backend. If you see
  those messages, the run found *your VU ceiling*, not the server's —
  raise `maxVUs` (and confirm there's no stray think-time) and re-run.

## When to use each

Phase the test types as the project matures:

1. **Always start with smoke.** Until smoke is green, nothing else
   is meaningful.
2. **Run average next** to confirm SLOs hold at production load.
3. **Run stress** to find the cliff and get the first set of
   findings.
4. **Run spike** if the customer cares about traffic surges
   (launches, marketing campaigns, news cycles).
5. **Run soak** before any deployment that introduces persistent
   state (caches, connection pools, in-memory caches).
6. **Run breakpoint** when you want a single number to report:
   "system handles X req/s before degrading".

## Local vs cloud per test type

Decided per-customer in workflow elicitation. The skill does **not**
hardcode this. See `local-vs-cloud.md`.

A typical decision matrix the customer may end up at:

| Test type   | Common choice                          |
|-------------|----------------------------------------|
| smoke       | local (validation)                     |
| average     | cloud (real measurement)               |
| stress      | cloud (reach the ceiling)              |
| spike       | local OR cloud (depends on target rate)|
| soak        | local (cheap) OR cloud (real LGs)     |
| breakpoint  | cloud (LG ceiling matters)            |

But every one of these is the customer's call.
