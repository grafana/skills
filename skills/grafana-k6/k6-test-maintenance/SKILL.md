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

Maintain, fix, and improve existing k6 test scripts. Five maintenance tasks,
each with a step-by-step procedure in [`references/workflows.md`](references/workflows.md):

1. **Threshold tightening** -- adjust threshold values based on observed metrics
2. **Version migration** -- update scripts for new k6 releases
3. **Service change adaptation** -- fix tests when the underlying service changes
4. **Refactoring** -- clean up and modernize test code
5. **Best practices audit** -- check scripts against current k6 best practices

## Core principle: behavior-aware change control

Classify every proposed change by whether it alters the test's runtime behavior:

- **Syntactic** (behavior unchanged): the k6 runtime produces identical metrics,
  pass/fail results, and endpoints. Examples: rename a variable, `let` → `const`,
  remove unused imports, update comments, reformat. **Apply directly.**
- **Behavioral** (behavior differs): anything affecting metrics, pass/fail,
  timing, request targets, or load shape. Examples: threshold value changes,
  adding `sleep()`, endpoint URL updates, check rewrites, scenario changes, new
  thresholds. **Always present as a diff with rationale and require confirmation.**

The threshold for "behavioral" is deliberately low. If in doubt, treat it as
behavioral and ask -- a trivial-looking threshold change can cascade to CI
gates, SLO calculations, and alerting.

## Dependencies

- **`k6-manage`** -- fetch and edit GCk6-hosted scripts safely (§5: GET, backup,
  edit, validate, PUT, verify by sha256). Read it before touching any
  cloud-hosted script.
- **`gcx`** -- sole tool for Grafana Cloud API access.
- **mcp-k6** tools -- `validate_script` and `get_documentation`. Check
  availability first; fall back to `k6 x docs` if absent.
- **`k6 x docs`** CLI -- documentation lookup when mcp-k6 isn't configured.
- **`k6` CLI** -- local validation (`k6 inspect`, `k6 run`).

## Validation loop (every edit)

Every workflow produces a modified script. Never present or PUT an unvalidated
script -- run this loop, fixing and re-running until it passes:

1. **Parse-check**: `k6 inspect <script>` -- catches syntax errors, invalid
   options, broken imports. Works on all types including browser tests (no
   browser needed). If mcp-k6 is available, also run `validate_script`.
2. **Local smoke** (non-browser, service reachable):
   `k6 run --vus 1 --iterations 1 <script>`.
3. **Classify the change** (below) and **verify per the matrix** -- recipes in
   [`references/verification.md`](references/verification.md).
4. **Cloud-hosted scripts**: apply via the k6-manage §5 safe-edit recipe
   (GET → backup → edit → validate → PUT as `application/octet-stream` →
   sha256-verify).

### Change classification

- **Class A -- declarative-config only.** The diff is confined to
  `options.thresholds` or similar declarative fields that don't alter what the
  k6 runtime executes; the bytes inside `default function`, imported modules,
  and check predicates are byte-identical. Example: `p(95)<500` → `p(95)<420`.
- **Class B -- runtime logic changes.** Any change to `default function`,
  imports, helper modules, request URLs, check predicates, or to
  `scenarios.*.vus`/`iterations`/`duration`/`executor` (which alter load shape
  and metric distributions). Example: changing a URL, adding a check, rewriting
  auth, switching executors.

When in doubt, treat as Class B.

### Verification matrix

| Class | Test duration | Verification |
|-------|---------------|--------------|
| **A** | any | sha256 + `k6 inspect` + **historical pass/fail prediction**. No cloud run needed. |
| **B** | short (< 5 min) | sha256 + `k6 inspect` + **full cloud run** (k6-manage §11). |
| **B** | long (≥ 5 min) | sha256 + `k6 inspect` + **local 1-iteration smoke** + **`k6 cloud run` of a local copy with `--vus 1 --iterations 1`**. PUT to the saved test only after the cloud smoke passes. |

Verification depth depends on the change class, not the test's duration -- most
edits don't need a full run, and production tests may run for hours. Per-class
recipes (Class A prediction table, Class B short/long, edge cases like scenario
changes and loosening) are in
[`references/verification.md`](references/verification.md).

## Documentation lookup

Before proposing any change that touches k6 APIs, imports, or patterns, confirm
it against current docs and **cite the source** in your report -- this grounds
recommendations in the real API, not stale model knowledge. Look up in order:

1. **mcp-k6** (preferred): `get_documentation("best_practices")`,
   `get_documentation("javascript-api/k6-browser")`, `validate_script(...)`.
2. **`k6 x docs`** CLI (always available):
   ```bash
   k6 x docs using-k6 thresholds
   k6 x docs javascript-api k6-http
   k6 x docs search "websocket migration"
   ```
   2-call strategy: try the direct path first; if it returns a topic list, pick
   the subtopic and call again. Full parent paths required (`using-k6 thresholds`,
   not `thresholds`). `k6 x docs` serves docs for the installed k6 version -- it
   may lag the target version when migrating.
3. **Web fetch** (last resort): `https://grafana.com/docs/k6/latest/`.

## Async check pattern

A common browser-test bug: using `check()` from `k6` with async predicates. The
built-in `check()` does not await Promises, so
`check(page, { 'title': p => p.locator('h1').textContent() === 'Foo' })` silently
passes because the Promise object is truthy. Two valid fixes:

- **Async-aware check from jslib**:
  `import { check } from 'https://jslib.k6.io/k6-utils/1.5.0/index.js'` -- then
  predicates can be `async` and `await` inside them works.
- **Resolve the value before the check**:
  `const text = await page.locator('h1').textContent(); check(text, { ... })` --
  keeps the standard sync `check` from `k6`.

When you hit this during any workflow (migration, refactor, audit), flag it as a
behavioral bug and propose one of these fixes.

## Script sources

- **GCk6-hosted** -- fetched and pushed via `k6-manage` §5 (GET → backup → edit →
  validate → PUT → verify sha256).
- **Local on disk** -- read and edit directly. Validate before presenting.

Determine the source before starting: a GCk6 test URL or ID is cloud-hosted; a
file path is local.

## Workflows

Full procedures are in [`references/workflows.md`](references/workflows.md):

- **[Threshold tightening](references/workflows.md#threshold-tightening)** --
  propose values with observed-metric justification, diff, apply, Class A verify.
- **[Version migration](references/workflows.md#version-migration)** -- find
  deprecated/renamed APIs, classify syntactic vs behavioral, apply, Class B verify.
- **[Service change adaptation](references/workflows.md#service-change-adaptation)**
  -- map each service change to a script change, propose fixes, Class B verify.
- **[Refactoring](references/workflows.md#refactoring)** -- find issues,
  auto-apply syntactic, propose behavioral, Class B verify after confirmation.
- **[Best practices audit](references/workflows.md#best-practices-audit)** --
  doc-driven audit across thresholds, load design, resource management, code
  quality, and browser specifics.

All five follow behavior-aware change control: auto-apply syntactic changes,
present behavioral ones as diffs for confirmation.

## Gotchas

| Issue | Detail |
|-------|--------|
| **Cloud script format** | GCk6 scripts can be single files or tar archives. Detect with `file(1)` before editing (see k6-manage §5). |
| **Zero-observation thresholds** | A threshold on a metric with no observations passes by default. When adding new thresholds, ensure the metric is actually emitted by the test. |
| **abortOnFail cascades** | If a threshold has `abortOnFail: true`, tightening it means runs abort earlier. Warn the user. |
| **Browser script validation** | Browser scripts can't be validated with `k6 run --iterations 1` without a browser. Use `k6 inspect` for parse-only validation, or `validate_script` via mcp-k6. |
| **k6 x docs version alignment** | `k6 x docs` serves docs for the installed k6 version; when migrating to a newer version, local docs may not reflect the target API. Note this in migration lookups. |
| **Script drift after edit** | After pushing a cloud-hosted script, the next run uses the new version, but historical runs keep their bundled snapshot. To investigate a past failure, compare the run-bundled script (read-only), not the current one. |

## References

- [`references/workflows.md`](references/workflows.md) -- step-by-step procedures for the five maintenance tasks
- [`references/verification.md`](references/verification.md) -- per-class post-edit verification recipes
