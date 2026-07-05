# Local vs Grafana Cloud k6

The skill's per-customer decision (recorded in `runbook.md` during
elicitation) determines where each of the six test types runs. This
doc is the reference for the tradeoffs and the framing.

## The framing

**Local is for validation. Cloud is for scale.**

- Local k6 confirms the *script* behaves correctly. All thresholds
  compile, all assertions hold, no scripting errors. A passing
  local smoke is a precondition for trusting cloud results.
- Cloud k6 confirms *the system under test* behaves correctly
  under realistic load. A single laptop usually cannot drive
  enough load to reach a production website's ceiling.

## Why a laptop often can't reach the ceiling

Typical limits a laptop hits before the SUT does:

- **CPU.** k6 itself uses CPU per VU; chromium uses ~1 core per
  browser VU. 50 protocol VUs + 1 browser VU often pegs an 8-core
  laptop.
- **Memory.** Each browser VU consumes ~1 GB RSS. Beyond 2-3
  browser VUs you hit swap and timings become meaningless.
- **NIC.** Saturating a 1 Gbit link from a single laptop is
  possible but rarely happens before CPU does.
- **TCP socket limits.** Many OSes default to ~28k ephemeral
  ports. At very high request rates you exhaust the pool.

The LG sidecar (see `lg-monitoring.md`) tells you which of these
you've hit.

A cloud LG fleet of 10 nodes lifts all of these limits by ~10×.
For most public websites, that's enough to find the cliff.

## The cost model

Grafana Cloud k6 bills in **virtual user hours (VUh)**:

- 1 protocol VU running for 1 hour = 1 VUh.
- 1 browser VU running for 1 hour = **10 VUh.**

Free-tier limits are finite and change over time. Always check
the Grafana Cloud k6 UI or `gcx` for current limits before
running long tests.

Budget-hostile test types:

| Test type   | VUh estimate (defaults)        | Risk            |
|-------------|--------------------------------|-----------------|
| smoke       | 3 VUs × 1m + 1 br × 1m ≈ 0.22 VUh | safe         |
| average     | 20 × 14m + 1 br × 14m ≈ 7 VUh  | safe            |
| stress      | 50 × 20m + 1 br × 20m ≈ 20 VUh | moderate        |
| spike       | 100 × 2m + 1 br × 2m ≈ 3.6 VUh | safe            |
| soak        | 10 × 70m + 1 br × 70m ≈ 23 VUh | **moderate-high** (browser VU runs long) |
| breakpoint  | up to maxVUs × 20m, no browser ≈ 30-100 VUh | **high** (variable) |

These are starting defaults. A 100-VU stress for 60 minutes is
~150 VUh; do it twice and you've used a typical small-tier budget.

## Decision matrix the customer typically lands at

| Test type   | Common choice                                           |
|-------------|---------------------------------------------------------|
| smoke       | local (validation, free, fast)                          |
| average     | cloud (real measurement; LG is unlikely to saturate)    |
| stress      | cloud (LG ceiling matters; need to reach the cliff)     |
| spike       | local or cloud — depends on target rate                 |
| soak        | local (no fleet cost) or cloud (real-LG fidelity)      |
| breakpoint  | cloud (LG ceiling materially affects the result)        |

But every cell is the customer's call. Some customers run
everything local; some run everything cloud. Don't override the
elicitation answer.

## The validation-then-measure flow

For any test type assigned to cloud:

1. **Local smoke** (always, even if smoke itself is cloud-bound).
   Catches scripting errors cheaply.
2. **Local short run** of the assigned test type (e.g. 2-minute
   subset of stress). Confirms thresholds compile and don't fire
   spuriously.
3. **Cloud run** of the full test type.
4. **Analyse** the cloud run via the Grafana Cloud k6 UI or via
   `gcx` for scripted access.

Skipping step 2 is a common cause of "10 VUh burned for a typo".

## Pushing to cloud

```bash
# After `k6 cloud login` succeeds:
k6 cloud run tests/wN-<short-name>/stress.js
```

The k6 binary will:

- Upload the script.
- Provision LG capacity per `options.cloud.distribution` (if set)
  or use the default region.
- Stream results back to your terminal.
- Print a final summary with a URL to the cloud test run.

Use the URL in the final report's Evidence section.

## When cloud results disagree with local

It happens. Reasons:

- **LG was saturated locally.** Cloud's headroom reveals the real
  ceiling.
- **Network path differs.** Cloud LGs may have lower latency to a
  CDN edge than your laptop does.
- **Geographic distribution.** Cloud `options.cloud.distribution`
  spreads VUs across regions; local is a single point.
- **IP allow-lists / WAFs.** Cloud LG IPs may be allow-listed
  differently from your laptop.

When in doubt: **trust cloud for measurement, trust local for
script validation.** That's the whole framing.

## Tool preference for cloud

If `gcx` is configured for Grafana Cloud k6, prefer it for:

- Listing recent test runs.
- Programmatic threshold queries.
- Downloading run summaries.

Use `mcp-k6` (if available) for in-session script work tied to a
cloud run.

For diagnosing a failed cloud test, open the run in the Grafana
Cloud k6 UI, inspect the thresholds tab, the per-metric timeline,
and any failed checks; then correlate with backend signals per
`grafana-investigation.md` if the user owns the backend.
