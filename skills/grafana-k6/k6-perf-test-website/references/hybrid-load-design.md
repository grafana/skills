# Hybrid load test design

Each test type ships as a hybrid: a **protocol scenario** that
drives the bulk of the load, plus a **single-VU browser scenario**
that measures Web Vitals under that load.

## Why hybrid

A protocol-only test measures backend throughput and latency well,
but says nothing about whether the **user-facing page** is still
responsive. A browser-only test measures Web Vitals correctly but
hits VU-count ceilings (browser VUs are expensive — typically
1 GB RSS per VU) long before you reach the backend's bottleneck.

Hybrid runs both: protocol VUs scale the load, the lone browser VU
acts as a "canary user" reporting LCP / INP / CLS / iteration
duration while the backend is stressed.

## Why one browser VU and not more

- One browser VU is enough to detect Web Vitals regressions caused
  by backend load. The page's `time-to-LCP` will visibly degrade
  when the backend slows.
- Adding more browser VUs roughly multiplies LG memory pressure
  without improving signal quality.
- A second browser VU adds noise to a breakpoint test (timing
  variance across pages obscures the cliff).

**Exception: breakpoint test omits the browser scenario entirely.**
The breakpoint is hunting protocol throughput; a single browser VU
mid-test adds noise without contributing.

## Scenario shape

```js
export const options = {
  userAgent: USER_AGENT,
  scenarios: {
    protocol: {
      executor: 'ramping-vus',     // or constant-vus / ramping-arrival-rate
      exec: 'protocolIteration',
      // ... ramp specific to test type ...
    },
    browser: {
      executor: 'constant-vus',
      exec: 'browserIteration',
      vus: 1,
      duration: '<matches protocol duration>',
      options: { browser: { type: 'chromium' } },
    },
  },
  thresholds: { /* SLOs + per-endpoint + per-iteration + web vitals */ },
};

export function protocolIteration() { /* ... */ }
export async function browserIteration() { /* ... */ }
```

## Why one file per test type rather than a `LOAD_TYPE` dispatcher

A single `load.js` with `const LOAD_TYPE = __ENV.LOAD_TYPE` and a
big `optionsByType` lookup is tempting. The skill rejects that in
favour of six separate files. Reasons:

1. **Each `options` block is self-documenting.** When you open
   `stress.js` you see immediately what the ramp does. No need to
   trace through a dispatch table.
2. **Tuning is per-test-type.** When you adjust the stress ramp
   from `0→50→0` to `0→80→0`, you change one file. The smoke
   defaults don't accidentally shift.
3. **Cloud config differs per type.** When pushing to Grafana
   Cloud k6, you often want different region distribution per
   test type. Per-file `cloud { distribution: ... }` is clean.
4. **The agent runs one type at a time.** No real workflow runs
   all six in one shell. Optimising for "all six in one file"
   optimises a case that never happens.
5. **Diffability.** When you tune average.js, the git diff is
   confined to that file. With the dispatcher, every tuning
   shows up as a diff to the same file, obscuring history.

## Why no shared `tests/lib/`

The bundled templates duplicate the iteration body across:

- `protocol.js` (functional)
- `browser.js` (functional)
- `smoke.js` (load)
- `average.js` (load)
- `stress.js` (load)
- `spike.js` (load)
- `soak.js` (load)
- `breakpoint.js` (load, protocol body only)

Across one workflow, that's roughly 8 copies. The skill **prefers
this duplication** to extracting a shared helper. Reasons:

1. **Incident-review readability.** During a post-mortem you read
   the failing test top-to-bottom. A file that imports four helpers
   from `tests/lib/` requires jumping around to understand what
   actually fired.
2. **Threshold tags are per-file.** The functional `protocol.js`
   uses `expect()`. The load `protocol` scenario uses `check()` +
   `tags`. A shared helper has to abstract over both, which adds
   complexity that doesn't repay itself.
3. **`sleep()` calls differ.** Functional tests don't sleep. Load
   tests insert randomised think-time between user actions. The
   sleep points are part of the workflow's identity in the load
   test.
4. **Browser iterations are async; protocol are sync.** Any shared
   helper has to be one or the other. Helpers that try to be both
   end up as awkward thin wrappers.
5. **Most tuning is per-file.** When you adjust the stress thresholds
   after seeing results, you touch `stress.js`. A shared helper
   reduces lines of diff but increases coupling.

The argument against duplication is "DRY". For perf test scripts,
the value of being able to *read one file and understand the
test* outweighs the cost of duplicating a 30-line iteration body
across six load files.

## What may be shared

A small set of constants is acceptable to share via `__ENV` or a
single top-of-file include:

- `BASE_URL`, `USER_AGENT`, test credentials — read from `__ENV`.
- A `restrictions` payload or canonical request body if it's
  re-used identically — declare once at the top of each file (not
  imported from a sibling).

What is **not** shared:

- The iteration body (sequence of `http.*` calls + `check()`).
- The threshold dictionary.
- The scenario options.

## Adding a new workflow later

The duplication makes adding a new workflow mechanical:

```bash
cp -R tests/workflow.template tests/wN-<short-name>
# Then for each .js in the new folder:
# - Replace <WORKFLOW_PLACEHOLDER> with wN-<short-name>
# - Edit the iteration body for the new user actions
# - Edit the per-endpoint thresholds for the new endpoints
```

A shared helper structure would require breaking the abstraction
to add a workflow with different timing or different endpoints,
which is most workflows.
