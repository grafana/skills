# Post-edit verification recipes

Detailed recipes for the verification matrix in `SKILL.md`. Classify the change
(Class A vs B) and test duration with the matrix, then follow the matching
recipe below.

## Contents

- [Class A: historical pass/fail prediction](#class-a-historical-passfail-prediction)
- [Class B short tests: full cloud run](#class-b-short-tests-full-cloud-run)
- [Class B long tests: local + cloud smoke](#class-b-long-tests-local--cloud-smoke)
- [Edge cases](#edge-cases)

## Class A: historical pass/fail prediction

For threshold-only changes, a fresh cloud run adds no information that the
existing historical data doesn't already provide. The metric values the new
threshold will evaluate are the same data the old threshold has been
evaluating, run after run. Verify deterministically:

1. Query the relevant metric aggregate across the last N completed runs
   using the multi-run endpoint (k6-manage references/metrics.md §8) -- use
   the same aggregate method as the threshold (`histogram_quantile(0.95)`
   for `p(95)`, `ratio` for rate thresholds, etc.).

2. For each historical value, mark pass/fail under the new threshold.

3. Present an impact table to the user **before** applying the change:

   ```
   | Run | Observed p95 | < 500 (old) | < 800 (new) |
   |-----|--------------|-------------|-------------|
   | R-3 | 380ms        | pass        | pass        |
   | R-2 | 520ms        | fail        | pass        |
   | R-1 | 850ms        | fail        | fail        |
   ```

4. If the proposed value is close to the observed peak, soft-warn:
   "headroom is X% over observed peak -- accept that a future run with
   normal variance might fail." Don't gate on user acknowledgement, just
   make it visible.

This is more informative than running once: a fresh run is just one more
sample on top of the existing N. The prediction table uses the entire
historical distribution.

## Class B short tests: full cloud run

Start the test via `POST /load_tests/{id}/start` (k6-manage §11), poll
`/test_runs/{id}` until `status=completed`, confirm `result=passed`. If
any thresholds failed, surface them with the same metric query you'd use
in trend analysis so the user can compare against the historical
distribution.

## Class B long tests: local + cloud smoke

The `POST /start` endpoint accepts no runtime overrides -- running the
saved test always runs it as-defined, for its full duration. Two layers of
verification avoid burning the full test:

1. **Local 1-iteration smoke** -- catches obvious bugs (broken selectors,
   import errors, runtime exceptions) for free:

   ```bash
   k6 run --vus 1 --iterations 1 script.js
   ```

   For browser tests, requires chromium locally. Skip this layer if
   chromium isn't installed; the cloud smoke below catches the same
   errors. Doesn't validate cloud-specific behaviour (load zones,
   distributed VUs, k6 cloud env vars, IP allowlists).

2. **`k6 cloud run` with CLI overrides on a local copy** -- validates
   cloud-side execution without the full duration:

   ```bash
   # Authenticate first (k6-manage §9)
   TOKEN=$(gcx --context <ctx> k6 auth token)
   STACK=$(gcx --context <ctx> config view --minify -o json | jq -r '.contexts[].grafana.server')
   k6 cloud login --token "$TOKEN" --stack "$STACK"

   # Run a local copy with overrides -- doesn't touch the saved test
   k6 cloud run --vus 1 --iterations 1 script.js
   ```

   For scripts where VUs/iterations live inside `scenarios.*` (CLI
   overrides don't apply to scenario-based configs), add a temporary
   `smoke` scenario at vus=1/iterations=1 to a local copy and run with
   `--scenario smoke`. PUT the unmodified original (without the smoke
   scenario) to the saved test after the smoke passes.

Only after both smoke layers pass do the PUT to the saved test. The next
scheduled run is the final long-term confidence check, but don't gate on
it -- the cloud smoke already validated cloud-side execution of the new
bytes.

## Edge cases

- **Changes to `scenarios.*.vus`, `duration`, or `iterations`** are
  declarative but alter runtime behaviour (different load → different
  metric distributions). Treat as Class B even though the diff is in the
  options block.
- **Loosening thresholds** is Class A and uses the same prediction
  recipe. Show which past failing runs would have passed under the new
  value; this surfaces the "you're hiding existing failures" risk
  explicitly. Loosening is allowed only when the user asks; don't propose
  it.
- **`k6 cloud run` requires a separate `k6 cloud login`** -- gcx auth
  doesn't carry over (see k6-manage §9). The login token is single-stack,
  so switching contexts requires re-login.
