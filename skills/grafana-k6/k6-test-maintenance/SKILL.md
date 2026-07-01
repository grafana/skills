---
name: k6-test-maintenance
description: >
  Maintain and improve existing k6 test scripts. Covers threshold tightening
  based on trend data, version migration between k6 releases, auto-fixing tests
  when the underlying service changes, refactoring for cleanliness, and auditing
  scripts against current best practices from docs. Use when the user asks to
  fix a failing k6 test, tighten thresholds, migrate a script to a new k6
  version, refactor a test, update a script after a service change, or improve
  a script with best practices. Trigger on phrases like "fix my k6 test",
  "tighten my thresholds", "migrate to k6 v2", "update my test script",
  "refactor this k6 test", "my test is failing after a deploy", "apply best
  practices to my script", "modernize my k6 test", or "the service changed and
  my test broke". Also trigger when another skill (k6-trend-analysis or
  k6-cloud-investigate-test) hands off with a recommendation to edit a script.
---

# k6 Test Maintenance

Maintain, fix, and improve existing k6 test scripts. This skill covers five
maintenance tasks:

1. **Threshold tightening** -- adjust threshold values based on observed metrics
2. **Version migration** -- update scripts for new k6 releases
3. **Service change adaptation** -- fix tests when the underlying service changes
4. **Refactoring** -- clean up and modernize test code
5. **Best practices audit** -- check scripts against current k6 best practices

## Core principle: behavior-aware change control

Every proposed change is classified by whether it alters the test's runtime
behavior:

- **Syntactic changes** (behavior unchanged): the k6 runtime would produce
  identical metrics, identical pass/fail results, and hit the same endpoints.
  Examples: rename a variable, `let` → `const`, remove unused imports, update
  comments, reformat code. These can be **applied directly**.

- **Behavioral changes** (behavior differs): anything that affects metrics,
  pass/fail outcomes, timing, request targets, or load shape. Examples:
  threshold value changes, adding `sleep()`, endpoint URL updates, check
  assertion rewrites, scenario changes, adding new thresholds. These are
  **always presented as a diff with rationale and require user confirmation**
  before applying.

The threshold for "behavioral" is deliberately low. If in doubt, treat it as
behavioral and ask. A threshold change that looks trivial can cascade to CI
gates, SLO calculations, and alerting.

## Dependencies

- **`k6-manage`** -- for fetching and editing GCk6-hosted scripts safely
  (Section 5: GET, backup, edit, validate, PUT, verify by sha256). Read it
  before touching any cloud-hosted script.
- **`gcx`** -- sole tool for Grafana Cloud API access.
- **mcp-k6** tools -- `validate_script` and `get_documentation` for script
  validation and doc lookup. Check availability first; if not available, fall
  back to `k6 x docs` CLI.
- **`k6 x docs`** CLI -- available for documentation lookup when mcp-k6 is not
  configured. Use the 2-call strategy: direct path first, then refine.
- **`k6` CLI -- for local validation (`k6 inspect`, `k6 run`).

## Mandatory pre-edit validation

Every workflow in this skill produces a modified script. Before presenting any
modified script to the user, validate it:

1. **Always run `k6 inspect <script>`** on the output. This is a parse-only
   check that catches syntax errors, invalid options, and broken imports. It
   works on all script types including browser tests (no browser needed).
2. If mcp-k6 is available, also run `validate_script` for deeper checking.
3. If the script is not a browser test and the target service is accessible,
   run `k6 run --vus 1 --iterations 1` as a smoke test.

If validation fails, fix the issue and re-validate before presenting. Never
present an unvalidated script to the user.

## Mandatory post-edit verification

After editing a cloud-hosted script, verify it took effect. Verification depth
depends on the **change class**, not test duration -- most edits don't need a
full run, and production tests may run for hours, so "just run it after editing"
doesn't work.

### Change classification

- **Class A -- declarative-config only.** The diff is confined to
  `options.thresholds` or similar declarative fields that don't alter what
  the k6 runtime executes. The bytes inside `default function`, imported
  modules, and check predicates are byte-identical. Example: tightening
  `p(95)<500` to `p(95)<420`, or loosening from 2000 to 2500.

- **Class B -- runtime logic changes.** Any change to `default function`,
  imports, helper modules, request URLs, check predicates, or to
  `scenarios.*.vus`/`iterations`/`duration`/`executor` (which alter load
  shape and metric distributions). Example: changing a URL, adding a new
  check, rewriting auth flow, switching executors.

When in doubt, treat as Class B. The threshold for "this is just config"
is deliberately narrow.

### Verification matrix

| Class | Test duration | Verification |
|-------|---------------|--------------|
| **A** | any | sha256 + `k6 inspect` + **historical pass/fail prediction**. No cloud run needed. |
| **B** | short (< 5 min) | sha256 + `k6 inspect` + **full cloud run** (k6-manage §11). |
| **B** | long (≥ 5 min) | sha256 + `k6 inspect` + **local 1-iteration smoke** + **`k6 cloud run` of a local copy with `--vus 1 --iterations 1`**. PUT to the saved test only after the cloud smoke passes. |

### Class A: historical pass/fail prediction

For threshold-only changes, a fresh run adds no information -- the new threshold
evaluates the same historical metric data the old one did. Verify deterministically:

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
   normal variance might fail." Make it visible; don't gate on acknowledgement.

The prediction table uses the entire historical distribution -- more informative
than one fresh sample.

### Class B short tests: full cloud run

Start the test via `POST /load_tests/{id}/start` (k6-manage §11), poll
`/test_runs/{id}` until `status=completed`, confirm `result=passed`. If
any thresholds failed, surface them with the same metric query you'd use
in trend analysis so the user can compare against the historical
distribution.

### Class B long tests: local + cloud smoke

`POST /start` runs the saved test as-defined for its full duration (no runtime
overrides), so verify with two smoke layers before the PUT:

1. **Local 1-iteration smoke** -- catches broken selectors, import errors, and
   runtime exceptions for free. Needs chromium for browser tests; skip if absent
   (the cloud smoke catches the same). Doesn't cover cloud-specific behaviour
   (load zones, distributed VUs, cloud env vars, IP allowlists).

   ```bash
   k6 run --vus 1 --iterations 1 script.js
   ```

2. **`k6 cloud run` on a local copy** -- validates cloud-side execution without
   the full duration:

   ```bash
   # Authenticate first (k6-manage §9)
   TOKEN=$(gcx --context <ctx> k6 auth token)
   STACK=$(gcx --context <ctx> config view --minify -o json | jq -r '.contexts[].grafana.server')
   k6 cloud login --token "$TOKEN" --stack "$STACK"

   # Local copy with overrides -- doesn't touch the saved test
   k6 cloud run --vus 1 --iterations 1 script.js
   ```

   If VUs/iterations live in `scenarios.*` (CLI overrides don't apply), add a
   temporary `smoke` scenario (vus=1/iterations=1) to a local copy, run with
   `--scenario smoke`, and PUT the unmodified original after it passes.

PUT to the saved test only after both smokes pass. The next scheduled run is the
final confidence check -- don't gate on it; the cloud smoke already validated the
new bytes cloud-side.

### Edge cases

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

## Mandatory documentation lookup

Before proposing any change that touches k6 APIs, imports, or patterns, confirm
it against current docs and **cite the source** in your report -- this grounds
recommendations in the real API, not stale model knowledge. Use the lookup
tiers and concrete commands in [Documentation lookup](#documentation-lookup) below.

## Async check pattern

A common bug in browser tests: using `check()` from `k6` with async predicates.
The built-in `check()` does not await Promises in predicates, so
`check(page, { 'title': p => p.locator('h1').textContent() === 'Foo' })` silently
passes because the Promise object is truthy.

Two valid fixes:
- **Use the async-aware check from jslib**:
  `import { check } from 'https://jslib.k6.io/k6-utils/1.5.0/index.js'`
  Then predicates can be `async` and `await` inside them works.
- **Resolve the value before the check**:
  `const text = await page.locator('h1').textContent(); check(text, { ... })`
  This keeps the standard sync `check` from `k6`.

When you encounter this pattern during any workflow (migration, refactor, audit),
flag it as a behavioral bug and propose one of these fixes.

## Script sources

This skill works with scripts from two sources:

- **GCk6-hosted** -- fetched and pushed via `k6-manage` Section 5. Follow the
  safe-edit recipe: GET → backup → edit → validate → PUT → verify sha256.
- **Local on disk** -- read and edit directly. Validate before presenting.

Determine which source the user is working with before starting. If they
provide a GCk6 test URL or ID, it's cloud-hosted. If they point to a file
path, it's local.

---

## Workflow: Threshold tightening

Typically triggered by `k6-trend-analysis` recommendations or user request.

### Step 1: Understand the current state

Gather the inputs:
- The current script (cloud or local)
- The current threshold definitions
- Trend data or metric observations that motivate the change (from
  `k6-trend-analysis` output, user-provided data, or fresh metric queries
  via `k6-manage`)

### Step 2: Propose new threshold values

For each threshold being tightened:
- State the **current value** and the **proposed value**
- Show the **observed metric** that justifies the change (e.g., "P95 is
  currently 380ms, proposing p(95)<450 to give 18% headroom")
- Note any **downstream impact**: does this threshold have `abortOnFail`?
  Is it referenced in CI gates or SLO definitions?

### Step 3: Present the diff

Show a clear before/after diff of the `thresholds` block. This is a
behavioral change -- always wait for user confirmation.

### Step 4: Apply and verify

After confirmation:
1. Apply the change to the script
2. Validate: `k6 inspect` (parse check) or `validate_script` (mcp-k6)
3. For cloud-hosted scripts, follow k6-manage Section 5 safe-edit recipe
   (backup → PUT → sha256-verify)
4. **Verify per "Mandatory post-edit verification" above.** Threshold
   changes are Class A -- use the historical pass/fail prediction recipe.
   For loosening, the prediction table also surfaces which past failing
   runs are being "hidden" by the change, which the user should see
   before the PUT.
5. Confirm the change was applied.

---

## Workflow: Version migration

Triggered when the user wants to update a script for a new k6 release, or when
deprecated APIs are detected.

### Step 1: Identify what needs migration

Read the script and look for:
- Deprecated imports (e.g., `k6/ws` → `k6/experimental/websockets`)
- Removed or renamed APIs
- Changed option formats (e.g., `ext.loadimpact` → `cloud`)
- Patterns that have newer alternatives

Use documentation to confirm migrations:
1. Check mcp-k6 `get_documentation` for migration guides (preferred)
2. Fall back to `k6 x docs using-k6 javascript-api` for API reference
3. Last resort: web fetch from `https://grafana.com/docs/k6/latest/`

### Step 2: Classify each change

For each required migration:
- **Is the API identical after the import swap?** (e.g., same function
  signatures, same behavior) → syntactic change, can auto-apply
- **Does the API differ?** (e.g., different method names, new patterns
  required) → behavioral change, must propose and confirm

### Step 3: Apply syntactic changes

Auto-apply all purely syntactic migrations (import path swaps where the API
surface is identical). Show a summary of what was changed.

### Step 4: Propose behavioral changes

For each migration that changes behavior:
- Show the old pattern and the new pattern side by side
- Explain what differs in behavior
- Cite the documentation source

Wait for user confirmation before applying each one.

### Step 5: Validate and verify

After all changes are applied:
1. Run `k6 inspect` or `validate_script` to confirm the script parses
2. **Verify per "Mandatory post-edit verification" above.** Migration
   edits are Class B by definition (imports and APIs changed), so choose
   the short-vs-long-test path based on the saved test's expected
   duration. Don't skip the cloud smoke for long tests just because the
   change "looks like a rename" -- migration bugs often hide in
   cloud-only behaviour (load-zone connectivity, env-var resolution).
3. Present the verification result.

---

## Workflow: Service change adaptation

Triggered when a test starts failing because the underlying service changed
(new endpoints, different response schema, changed auth), or when
`k6-cloud-investigate-test` hands off after identifying a service-side cause.

### Step 1: Understand what changed

Gather evidence of what changed on the service side:
- If coming from `k6-cloud-investigate-test`: read the investigation report
  for the specific failure details (error messages, status codes, response
  bodies)
- If the user describes the change: confirm the specifics (what endpoint
  changed, what the new behavior is)
- If neither: fetch the most recent failing run's logs via `k6-manage`
  Section 4 and compare with the last passing run to identify the delta

### Step 2: Categorize the changes needed

Map each service change to a script change:

| Service change | Script impact | Complexity |
|---------------|--------------|------------|
| Endpoint URL changed | Update URL string | Simple if new URL known |
| Response field renamed | Update check assertions | Moderate |
| New required header/param | Add to request config | Moderate |
| Auth mechanism changed | Rewrite auth flow | Complex |
| Response schema restructured | Rewrite extraction + checks | Complex |
| Endpoint removed/replaced | Rewrite entire request | Complex |

### Step 3: Propose fixes

For each change:
- Show the current failing code and the proposed fix
- Explain the rationale (what changed on the service side)
- All of these are behavioral changes -- present as a diff with rationale

For complex changes where the "right" fix depends on user intent:
- Present multiple options if applicable
- Flag what you're uncertain about
- Ask the user to clarify before proceeding

### Step 4: Validate and verify

After confirmation and applying changes:
1. Validate with `k6 inspect` or `validate_script`
2. **Verify per "Mandatory post-edit verification" above.** Service-change
   fixes are Class B (request URLs, check predicates, or auth flow
   changed). The cloud smoke is especially important here -- a fix that
   works locally against your laptop's network may still hit the wrong
   host or fail auth from cloud load zones.
3. Confirm the previously-failing checks now pass against the new
   service shape.

---

## Workflow: Refactoring

Triggered by user request to clean up or modernize a test script.

### Step 1: Read and analyze the script

Look up best practices in the docs before analyzing -- don't rely on model
knowledge alone. Run `k6 x docs using-k6-browser/recommended-practices` for
browser tests, `k6 x docs using-k6 thresholds` for threshold patterns, etc.

Identify issues:
- Dead code (unused variables, unreachable branches)
- Duplicated logic that could be extracted to helper functions
- Overly complex structure that could be simplified
- Inconsistent naming or patterns
- Missing error handling (e.g., no `try/finally` for browser tests)
- Deprecated patterns (e.g., `waitForNavigation`, `networkidle`, `type()`
  instead of `fill()`)
- Async bugs (e.g., async methods inside sync `check()` predicates)
- Missing thresholds or performance guards

Be thorough. The user asked for a refactor -- find everything, even if some
findings are behavioral. The classification framework exists to handle this:
you'll auto-apply the syntactic ones and propose the behavioral ones. Don't
self-censor by leaving out findings you're unsure about -- classify them and
let the user decide.

### Step 2: Classify each change

Apply the behavior-aware rule:
- **Syntactic** (auto-apply): variable renames, `let` → `const`, remove
  unused imports, reformat, add/update comments, extract pure helper functions
  that don't change call semantics
- **Behavioral** (propose + confirm): adding `try/finally` error handling,
  restructuring scenarios, changing group boundaries, extracting logic that
  changes execution order

### Step 3: Apply and propose

1. Auto-apply all syntactic changes to the output script
2. Do NOT apply behavioral changes to the output script -- describe them in
   the report as proposals with diffs and rationale
3. The output script should reflect ONLY syntactic fixes so the user can see
   what was safely changed vs what needs their approval
4. Run `k6 inspect` on the output script to validate it

### Step 4: Apply behavioral changes after confirmation

Once the user confirms, apply behavioral changes, re-validate, then
**verify per "Mandatory post-edit verification" above**. A refactor that
"shouldn't change behaviour" still needs Class B verification because the
classification is about the diff, not the intent -- if any runtime byte
changed, treat it as Class B.

---

## Workflow: Best practices audit

Triggered by user request, or as a secondary check during any other maintenance
workflow. Uses documentation to identify improvements.

### Step 1: Establish the documentation source and look up best practices

This step is not optional. Look up documentation before auditing -- do not
rely solely on model knowledge.

Try in order:
1. **mcp-k6**: call `get_documentation` for best practices
2. **`k6 x docs`**: run `k6 x docs using-k6` for general guidance, then
   topic-specific lookups as needed (e.g.,
   `k6 x docs using-k6-browser/recommended-practices` for browser tests)
3. **Web fetch**: `https://grafana.com/docs/k6/latest/` as last resort

For browser tests specifically, look up:
- `k6 x docs using-k6-browser/recommended-practices`
- `k6 x docs javascript-api k6-browser page`
- `k6 x docs javascript-api k6-browser locator`

### Step 2: Audit the script

Check against these categories:

**Thresholds and assertions:**
- Are thresholds defined? (At minimum: `http_req_duration` and
  `http_req_failed` for HTTP tests)
- Are `check()` or `expect()` assertions on every response?
- Are thresholds realistic based on the test type?

**Load design:**
- Is `sleep()` present in load tests? (Required for realistic think time)
- Are scenarios using appropriate executors for the test type?
- Is the VU/iteration count reasonable?

**Resource management:**
- Browser tests: `try/finally` with `page.close()` in `finally`?
- gRPC tests: `client.close()` after each iteration?
- File handles and connections properly closed?

**Code quality:**
- `const` instead of `let`/`var` at module level?
- No deprecated imports?
- No hardcoded secrets? (Should use `__ENV` or environment variables)
- SharedArray for test data files?

**Browser-specific** (if script imports `k6/browser`):
- Using `getBy*` APIs (`getByRole`, `getByLabel`, `getByText`,
  `getByTestId`) instead of generic `page.locator()` where possible?
- Not calling `waitFor()` before interactions (built-in actionability)?
- Not using `waitForLoadState()` after navigation?
- Using `page.waitForTimeout()` instead of `sleep()` in browser context?

### Step 3: Present findings

Produce an audit report:

```markdown
## Best Practices Audit: {script_name}

### Passed
- [x] Thresholds defined
- [x] Checks on responses
- [x] sleep() between iterations

### Needs attention (behavioral changes -- requires confirmation)
- [ ] **Add try/finally for browser cleanup**: page.close() is not in a
      finally block. If a test step throws, the browser page leaks.
      [Doc: k6 x docs javascript-api k6-browser page]
- [ ] **Use getByRole instead of locator**: 3 instances of
      page.locator('input[name="..."]') could use getByRole('textbox').
      [Doc: k6 x docs javascript-api k6-browser locator]

### Auto-applied (syntactic -- no behavior change)
- [x] Changed 2 `let` declarations to `const` (lines 12, 45)
- [x] Removed unused import `encoding` (line 3)
```

### Step 4: Produce the output script

Apply syntactic changes to a copy of the script and save it. Behavioral
changes should be described in the report but NOT applied to the output
script -- they are proposals awaiting confirmation. The output script should
contain only the syntactic (auto-applied) fixes so the user can see the
safe changes separately from the proposed behavioral ones.

Run `k6 inspect` on the output script to validate it parses correctly.

### Step 5: Apply behavioral changes after confirmation

Once the user confirms specific behavioral changes, apply them to the script,
re-validate, and **verify per "Mandatory post-edit verification" above**.
Audit-driven changes are Class B by default.

---

## Documentation lookup

When you need to check k6 API details, migration guides, or best practices:

### mcp-k6 (preferred)
```
get_documentation("best_practices")
get_documentation("javascript-api/k6-browser")
validate_script(script_content)
```

### k6 x docs CLI (fallback)
```bash
k6 x docs using-k6 thresholds
k6 x docs javascript-api k6-http
k6 x docs search "websocket migration"
```

Use the 2-call strategy: try the direct path first. If it returns a topic
list instead of content, pick the right subtopic and call again. Full parent
paths are required (e.g., `using-k6 thresholds` not just `thresholds`).

### Web fetch (last resort)
```
https://grafana.com/docs/k6/latest/using-k6/thresholds/
https://grafana.com/docs/k6/latest/javascript-api/
```

---

## Gotchas

| Issue | Detail |
|-------|--------|
| **Cloud script format** | GCk6 scripts can be single files or tar archives. Detect with `file(1)` before editing (see k6-manage Section 5). |
| **Zero-observation thresholds** | A threshold on a metric with no observations passes by default. When adding new thresholds, ensure the metric is actually emitted by the test. |
| **abortOnFail cascades** | If a threshold has `abortOnFail: true`, tightening it means runs will abort earlier. Warn the user about this. |
| **Browser script validation** | Browser scripts can't be validated with `k6 run --iterations 1` without a browser available. Use `k6 inspect` for parse-only validation, or `validate_script` via mcp-k6. |
| **k6 x docs version alignment** | `k6 x docs` serves docs for the version of k6 installed. If migrating to a newer version, the local docs may not reflect the target version's API. Note this when using it for migration lookups. |
| **Script drift after edit** | After pushing a cloud-hosted script, the next run uses the new version. But historical runs keep their bundled snapshot. If investigating a past failure, compare the run-bundled script (read-only) not the current one. |
