# Session health, ranking, and fixes

Classify from the dump only. Prefer an explicit `rating` on a vital over recomputing.

## Outcome

| Outcome | When |
|---|---|
| **error** | Any `kind=exception`, HTTP status `0` or `5xx`, or mobile ANR |
| **degraded** | Poor web vitals, slow cold/warm start, frozen/slow frames or `app.jank`, HTTP `4xx`, error-level logs, rage clicks — and no error-tier issue |
| **healthy** | Journey present, no exceptions, no failed HTTP, web vitals and mobile startup/jank good or absent |
| **unknown** | Empty dump, or too little signal to judge |

A session can be **degraded** even when the user finished a flow (e.g. LCP poor but checkout completed).

## Rank problems (highest first)

1. **Exceptions** — `kind=exception` or exception type/value columns. Critical.
2. **Failed HTTP** — status `0` (network/CORS/abort) or `5xx`. Critical. `4xx` is warning unless it blocks the flow.
3. **ANR / freeze** — `type=anr`, `type=app_frozen_frame` / `value_frozen_frames`, or event `app.jank` if present.
4. **Poor performance** — web: `kind=measurement type=web-vitals` with `rating=poor`. Mobile: slow `type=app_startup` (cold vs warm), `type=app_frames_rate` / `type=app_frozen_frame`, or event `app.jank`.
5. **Error logs** — `kind=log` and `log_level`/`level` of `error` or `warn` that explain a user-visible failure.
6. **Rage / retry** — ≥3 of the same user action on the same view/page within ~1.5s. Info, unless it precedes an exception.

Deduplicate consecutive identical exceptions (same type + template/hash). Report first timestamp, count, and last timestamp.

Skip `faro_internal_*`, `session_resume`, `session_extend`, and raw `performanceEntry` rows unless they are the only signal.

## Performance signals (if no `rating`)

**Web**

| Metric | Good | Poor |
|---|---|---|
| LCP | ≤ 2500 ms | > 4000 ms |
| INP | ≤ 200 ms | > 500 ms |
| CLS | ≤ 0.1 | > 0.25 |
| TTFB | ≤ 800 ms | > 1800 ms |

Use the dump’s units (ms vs seconds). CLS is a score, not ms.

**Mobile** — RN and Flutter send measurements (`kind=measurement`). Loki flattens each `values` key as `value_<key>` (same names the SDKs use: `appStartDuration`, `coldStart`, `slow_frames`, `frozen_frames`).

| `type` | How to read |
|---|---|
| `app_startup` | Duration: `value_appStartDuration` (ms). `value_coldStart=1` → cold (fresh process); `0` → warm (resume from background). Call out slow starts relative to other starts in the dump, or when duration is seconds not hundreds of ms. |
| `app_frames_rate` | `value_slow_frames` — slow frames (degraded). |
| `app_frozen_frame` | `value_frozen_frames` — frozen frames (error-tier, with ANR). |
| `anr` | Application not responding. |

If the dump has events `app.startup` or `app.jank` (native OTel / newer clients), use those too: `app.jank.threshold` ≈ `0.016` (slow) vs ≈ `0.700` (frozen).

## How to fix it (typical)

Pick the remediations that match **this** dump. Do not list the whole catalog.

| Signal | Where to look | Typical fix |
|---|---|---|
| Exception | Message, stack/template, `page_id` / view, nearby user action | Fix the throwing code; ship source maps / native symbols; confirm the app version in metadata is the build you think it is |
| HTTP 5xx | `http_url`, method, status, `traceID` | Open the trace in Tempo; fix the backend or timeout; check the release that matches `app_version` |
| HTTP 0 | URL + timing vs navigation | CORS, mixed content, ad-blocker, offline, request abort on route change |
| HTTP 4xx | URL + whether the user retried | Auth/session expiry, wrong path, feature-flagged API |
| LCP poor | `type=web-vitals` `value_lcp` (and `rating` if present), nearby TTFB | Smaller hero image, server TTFB, preload LCP resource, avoid late-injected hero |
| INP poor | `value_inp` / interaction target if present | Break up long handlers, reduce main-thread work |
| CLS poor | `value_cls` / largest shift if present | Reserve image/ad size, avoid inserting above-the-fold nodes |
| Slow cold/warm start | `type=app_startup` `value_appStartDuration` + `value_coldStart`, device/OS, app version | Defer work off the launch path; cold vs warm tells you process-create vs resume |
| Slow / frozen frames | `value_slow_frames` / `value_frozen_frames`, or `app.jank` if present, nearby view | Main-thread work, native plugin, heavy list at that view |
| ANR | Device/OS, app version, nearby view | Same as freeze — native thread blocked |
| Rage clicks | Same `action_name` / view cluster | Unresponsive control; correlate with INP or a following exception |
| Missing replay | No `session_replay_start` | Session not sampled for recording — do not claim video exists |

If `traceID` is present on a problem, include the **id** in that item. Offer Tempo / `gcx traces get` as a **follow-up** for that id only — not a URL on every error.
