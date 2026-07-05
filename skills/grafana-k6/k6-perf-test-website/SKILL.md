---
name: k6-perf-test-website
description: >
  Use when the user wants to performance-test, load-test, or stress-test
  a public website end-to-end with k6. Produces a hybrid (protocol +
  browser) test suite, SLO-backed thresholds, a load-generator monitor
  sidecar, and a Grafana-side investigation playbook for backends the
  user owns. Triggers on "perf test my site", "performance test my
  site", "load test this URL",
  "stress test my web app", "I want to load test [URL]", "set up k6
  against my website", "write a k6 suite for [site]", "see if my site
  handles N concurrent users", or "how does my site perform under
  traffic". Use this skill whenever the user mentions k6, load testing,
  stress testing, performance testing, or wants to validate a website
  under traffic — even if they don't explicitly use the word "test" or
  ask for the specific outputs this skill produces.
---

# `k6-perf-test-website`

An end-to-end, opinionated workflow for performance-testing any
public website with k6. The skill produces:

- A scaffolded project with one folder per user-described workflow.
- Functional protocol + browser tests (must pass before load testing).
- Hybrid load tests (protocol scenario + 1 browser VU) per test type
  (smoke / average / stress / spike / soak / breakpoint).
- SLO-backed thresholds with per-endpoint tagging and Web Vitals.
- A cross-platform load-generator monitor sidecar.
- Optional Grafana-side investigation when the user owns the backend.
- A structured Markdown report at the end.

This skill enforces a few opinions you should not silently override:

- **Always elicit workflows first.** Don't guess.
- **Functional tests must be green before load tests run.**
- **Always monitor the load generator** — server-looks-slow is often
  laptop-looks-slow.
- **Local for validation, cloud for scale** — but ask the user where
  to run each test type; don't hardcode.
- **No shared `tests/lib/`.** Iteration-body duplication is preferred;
  each script reads cleanly on its own during incident review.

## Prerequisites

- **k6 ≥ v2.0.0** (`k6 version`) — required for stable `k6/browser`,
  `expect()`, async/await iteration functions, and per-request `tags`.
- **Node.js ≥ 20** + npm.
- **Playwright** with the Chromium download
  (`npx playwright install chromium`).
- **`har-to-k6`** (`npm i -D har-to-k6`).
- Network access from the load-generator host to the target site.

Tools the skill prefers when installed:

- `mcp-k6` — script creation, Playwright→k6/browser migration, API
  lookup. Prefer over hand-writing k6 boilerplate.
- `mcp-grafana` — in-session Prometheus/Loki/Tempo/Pyroscope queries
  during §9 backend investigation.
- `gcx` — Grafana Cloud CLI for shell-friendly queries, datasource
  discovery, and Grafana Cloud k6 cloud-run dispatch.
- `k6` binary — local validation runs and breakpoint hunting.
- `k6 x docs` (xk6-docs) — look up k6 API surface when writing or
  editing scripts without `mcp-k6` available.

If these tools are not configured the skill falls back to plain CLI
tools (`k6`, `npx`, `curl`) and hand-written scripts. The skill does
not own toolchain setup; defer to the user's existing setup process.

Explicit non-goals:

- Protocol-only suites (out of scope for this skill).
- API-only / non-browser apps.
- Mobile-native testing.
- Capacity planning beyond finding and tagging a breakpoint.

## Workflow overview

Tick these off in order. Each step has a section below.

1. Elicit workflows from the user. [§1](#1-elicit-workflows)
2. Scaffold the project from `assets/`. [§2](#2-scaffold-the-project)
3. Record each workflow with Playwright. [§3](#3-record-each-workflow)
4. Build functional protocol + browser tests; run `tests/run-all.sh`
   until green. [§4](#4-build-functional-tests)
5. Design SLO-backed thresholds and per-endpoint tags.
   [§5](#5-design-slos-and-thresholds)
6. Build hybrid load tests, one file per test type.
   [§6](#6-build-hybrid-load-tests)
7. Run validation locally with the LG sidecar.
   [§7](#7-run-locally-with-lg-sidecar)
8. Push to Grafana Cloud k6 for the test types the user chose for
   cloud. [§8](#8-push-to-grafana-cloud-k6)
9. Investigate the backend with Grafana (if owned).
   [§9](#9-investigate-the-backend)
10. Report back to the user. [§10](#10-report-back)

## 1. Elicit workflows

**The single most important step.** Without explicit workflows, every
later step is guesswork.

Ask the user the questions in `references/workflow-elicitation.md`
and record answers in a `runbook.md` alongside the scaffolded project.

You must capture: 2-4 named workflows, credentials, read vs write,
destructive actions to avoid during soak, worry list, existing SLOs,
backend ownership and Grafana access, and **per test type** whether
each runs locally or in Grafana Cloud k6.

If the user can't name at least one workflow, **stop and clarify**;
do not proceed.

## 2. Scaffold the project

Copy the `assets/` tree from this skill into the user's chosen
directory. The skill's `assets/` directory is at `<SKILL_DIR>/assets/`,
where `<SKILL_DIR>` is the absolute path to this skill's directory —
your harness exposes this (e.g. opencode prefixes skill metadata with
a `Base directory for this skill:` line). If you can't determine
`<SKILL_DIR>` from context, ask the user.

```bash
cp -R "<SKILL_DIR>/assets/." "<target-dir>/"
```

If `cp -R` is blocked by sandbox permissions, copy files individually
via your agent's file-write tool.

The scaffolded layout:

```
<target-dir>/
├── package.json
├── .gitignore
├── README.md
├── runbook.md                       # you create from §1 answers
├── recordings/
│   ├── README.md
│   └── scripts/
│       └── recorder.template.js     # copy per workflow → wN-<short-name>.js, …
├── tests/
│   ├── run-all.sh
│   └── workflow.template/           # copy per workflow → wN-<short-name>/, …
│       ├── from-har.js
│       ├── protocol.js
│       ├── browser.js
│       ├── smoke.js
│       ├── average.js
│       ├── stress.js
│       ├── spike.js
│       ├── soak.js
│       └── breakpoint.js
└── tools/
    ├── lg-monitor.sh
    └── run-with-monitor.sh
```

For each workflow: copy `recorder.template.js` → `recordings/scripts/wN-<short-name>.js`,
copy `tests/workflow.template/` → `tests/wN-<short-name>/`, and
replace `<WORKFLOW_PLACEHOLDER>` markers with the workflow's short name.

Then install:

```bash
cd <target-dir> && npm install && npx playwright install chromium
```

## 3. Record each workflow

Per workflow:

1. Fill in `recordings/scripts/wN-<short-name>.js`: user-action sequence,
   `recordHar.urlFilter` regex (allow-list the target host; block
   third-party RUM/ads — see `references/recording-with-playwright.md`),
   and a real Chrome `userAgent` (the default `HeadlessChrome` UA
   triggers bot-blocking on many sites).
2. Run: `node recordings/scripts/wN-<short-name>.js` → writes `recordings/har/wN-<short-name>.har`
3. Convert: `npx har-to-k6 recordings/har/wN-<short-name>.har -o tests/wN-<short-name>/from-har.js`
4. Commit both HAR and `from-har.js` (audit trail for bundle-path changes).

If the recorder fails or produces an unusable HAR (bot-blocking,
missing hydration, third-party noise), see the Recording section of
`references/gotchas.md` and `references/recording-with-playwright.md`.

Prefer `mcp-k6` recording and migration tools if available.

## 4. Build functional tests

Per workflow:

1. Hand-clean `from-har.js` into `protocol.js` — drop per-request
   UA headers, rename groups, parameterise `BASE_URL`, replace session
   tokens, drop `sleep(1)`, add `expect()` on every load-bearing
   response. Full procedure in `references/functional-tests.md`.
2. Hand-write `browser.js` from the Playwright recorder using the
   5-step procedure in `references/functional-tests.md`.
3. Run `./tests/run-all.sh`. **Do not proceed to §5 until it exits 0.**

Prefer `mcp-k6` migration tools for Playwright→k6/browser conversion.

## 5. Design SLOs and thresholds

Adjust the opinionated defaults in `assets/tests/workflow.template/`
to the user's stated SLOs from §1. Four layers:

1. **Global SLOs** — overall error rate + aggregate latency.
2. **Per-endpoint thresholds** — tag every protocol request, threshold per tag.
3. **Per-iteration thresholds** — workflow time + iteration completion rate.
4. **Web Vitals** — LCP/INP/CLS only (no FCP).

Default globals:

```js
http_req_failed: ['rate<0.01'],
http_req_duration: ['p(95)<500'],
checks: ['rate>0.99'],
```

Per-endpoint tagging:

```js
http.get(`${BASE_URL}/api/things`, { tags: { name: 'GetThings' } });
'http_req_duration{name:GetThings}': ['p(95)<400', 'p(99)<800'],
```

Web Vitals:

```js
browser_web_vital_lcp: ['p(95)<2500'],
browser_web_vital_inp: ['p(95)<200'],
browser_web_vital_cls: ['p(95)<0.1'],
```

See `references/slo-design.md` for per-iteration tuning, the
`performance.mark` custom-Trend pattern, `iteration_completed` Rate,
breakpoint abort-on-fail thresholds, and loosening rules.

## 6. Build hybrid load tests

Per workflow, one file per test type. Each file has a protocol scenario
(drives load) plus a single browser VU (measures Web Vitals under load).
Breakpoint is protocol-only — a browser VU adds noise to the signal.

| Type       | Executor             | Defaults                                 |
|------------|----------------------|------------------------------------------|
| smoke      | constant-vus         | 3 VUs × 1m                               |
| average    | ramping-vus          | 0→20→0 over 14m                          |
| stress     | ramping-vus          | 0→50→0 over 20m                          |
| spike      | ramping-vus          | 0→100→0 over 2m                          |
| soak       | ramping-vus          | 0→10→0 over 70m                          |
| breakpoint | ramping-arrival-rate | 5/s→500/s over 20m, abortOnFail          |

Tune per workflow once you've seen smoke results. See
`references/test-types.md` for rationale and `references/hybrid-load-design.md`
for why one file per type and why duplication between files is acceptable.

## 7. Run locally with LG sidecar

```bash
./tools/run-with-monitor.sh tests/wN-<short-name>/smoke.js
```

Starts `lg-monitor.sh` in the background, runs k6, then prints a
summary verdict: **OK** (≥30% idle), **NOTE** (10–30%), or **WARNING**
(<10%). If WARNING, the laptop is the bottleneck — reduce VUs, switch
to cloud, or split across multiple LGs. See `references/lg-monitoring.md`.

## 8. Push to Grafana Cloud k6

For each test type assigned to cloud in the §1 runbook:

1. Confirm `k6 cloud login` works (the skill does not own auth setup).
2. Run smoke locally first to validate the script.
3. `k6 cloud run tests/wN-<short-name>/<type>.js`
4. Capture the run URL for the §10 report.

**Cost reminder:** browser VU-hours are billed 10× protocol VU-hours.
Soak and breakpoint are the most expensive. Check limits before long runs.
See `references/local-vs-cloud.md`.

## 9. Investigate the backend

Only if the user owns the backend and has Grafana access.

1. Discover datasources via `mcp-grafana` or `gcx datasources list`.
2. Ask the user for service label keys — do not guess.
3. Correlate the k6 run window with RED metrics, error logs, traces,
   and profiles (Pyroscope — use explicit `from`/`to` for the run window).
4. Hand back specific evidence: timestamps, query strings, panel links.

See `references/grafana-investigation.md` for the full flow including
how to verify absence before reporting it.

## 10. Report back

Fill in the report template from `references/reporting.md`:

- **Summary** — workflows, test types, dates
- **SLOs** — pass/fail per threshold
- **Findings** — one paragraph per finding, ordered by severity, with specific evidence
- **Evidence** — k6 output paths, LG monitor CSVs, cloud run URLs, Grafana links
- **Suggested next steps**

Always be specific. "Latency is high" is not a finding. "GetPizza
p(95) hit 1.4s at iteration ~200; correlated with sustained 100% CPU
on the recommender service per Grafana panel link" is.

---

## Reference index

- [`references/workflow-elicitation.md`](references/workflow-elicitation.md) — verbatim question script for §1.
- [`references/recording-with-playwright.md`](references/recording-with-playwright.md) — HAR capture, third-party filter regex, hydration signals.
- [`references/functional-tests.md`](references/functional-tests.md) — 5-step Playwright→k6/browser conversion procedure.
- [`references/hybrid-load-design.md`](references/hybrid-load-design.md) — protocol + 1 browser VU rationale, duplication argument.
- [`references/slo-design.md`](references/slo-design.md) — full threshold rationale, async vs sync metric capture.
- [`references/test-types.md`](references/test-types.md) — definitions and defaults for all six test types.
- [`references/lg-monitoring.md`](references/lg-monitoring.md) — why the sidecar exists, how to read its output.
- [`references/local-vs-cloud.md`](references/local-vs-cloud.md) — framing, cost model, per-test-type tradeoffs.
- [`references/grafana-investigation.md`](references/grafana-investigation.md) — generic backend investigation flow.
- [`references/gotchas.md`](references/gotchas.md) — generic pitfalls.
- [`references/reporting.md`](references/reporting.md) — final report template.
