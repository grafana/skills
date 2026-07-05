# Performance tests

Scaffolded by the `k6-perf-test-website` skill. End-to-end k6 perf
test suite using a hybrid protocol + browser approach.

## Layout

```
.
├── package.json              # Playwright + har-to-k6
├── runbook.md                # workflows, credentials, run plan
├── recordings/
│   ├── scripts/              # Playwright recorder per workflow (wN-<short-name>.js)
│   └── har/                  # HAR captures, committed
├── tests/
│   ├── run-all.sh            # functional-test driver (must exit 0)
│   ├── workflow.template/    # copy this per workflow
│   └── wN-<short-name>/      # one folder per workflow
│       ├── from-har.js       # har-to-k6 output, committed for audit
│       ├── protocol.js       # functional protocol test
│       ├── browser.js        # functional browser test
│       ├── smoke.js          # hybrid smoke
│       ├── average.js        # hybrid avg load
│       ├── stress.js         # hybrid stress
│       ├── spike.js          # hybrid spike
│       ├── soak.js           # hybrid soak
│       └── breakpoint.js     # protocol-only ramping breakpoint
└── tools/
    ├── lg-monitor.sh         # cross-platform LG sidecar
    └── run-with-monitor.sh   # k6 wrapper + summary
```

## Quick start

```bash
# 1. Install
npm install
npx playwright install chromium

# 2. Record each workflow (one-time per workflow)
node recordings/scripts/wN-<short-name>.js
npx har-to-k6 recordings/har/wN-<short-name>.har -o tests/wN-<short-name>/from-har.js
# ... then hand-clean from-har.js into protocol.js and browser.js
#     (see skill reference: functional-tests.md)

# 3. Verify functional tests pass
./tests/run-all.sh

# 4. Run a load test with the LG monitor sidecar
./tools/run-with-monitor.sh tests/wN-<short-name>/smoke.js
./tools/run-with-monitor.sh tests/wN-<short-name>/average.js
./tools/run-with-monitor.sh tests/wN-<short-name>/stress.js
# ... etc per the run plan in runbook.md

# 5. (If cloud) push to Grafana Cloud k6
k6 cloud run tests/wN-<short-name>/stress.js
```

## Run plan

See `runbook.md` for:

- Per-workflow definitions and credentials.
- SLOs.
- Which test types run locally vs in Grafana Cloud k6.
- Constraints (IP allow-lists, rate limiters, etc.).

## Where output goes

- Functional test logs: `${TMPDIR}/k6-run-all/`
- Load test logs + LG monitor CSVs: `/tmp/perf-lg-monitor/`
- k6 cloud runs: Grafana Cloud k6 web UI (links in run-all.sh
  output).

## Adding a workflow

```bash
# Copy template
cp -R tests/workflow.template tests/wN-<short-name>
cp recordings/scripts/recorder.template.js recordings/scripts/wN-<short-name>.js

# Replace <WORKFLOW_PLACEHOLDER> markers in each copied file
grep -rl '<WORKFLOW_PLACEHOLDER>' tests/wN-<short-name> recordings/scripts/wN-<short-name>.js \
  | xargs sed -i.bak "s/<WORKFLOW_PLACEHOLDER>/wN-<short-name>/g" \
  && find tests/wN-<short-name> recordings/scripts -name '*.bak' -delete

# Fill in the per-workflow body
$EDITOR recordings/scripts/wN-<short-name>.js
node recordings/scripts/wN-<short-name>.js
npx har-to-k6 recordings/har/wN-<short-name>.har -o tests/wN-<short-name>/from-har.js
# hand-clean from-har.js → protocol.js + browser.js
./tests/run-all.sh
```
