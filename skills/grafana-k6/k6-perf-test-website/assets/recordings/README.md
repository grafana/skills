# Recordings: Playwright source-of-truth → HAR → k6 scripts

Source of truth for `tests/`. Each workflow has one Playwright
recorder in `scripts/` and one HAR in `har/`.

## Pipeline

```
recordings/scripts/wN-<short-name>.js          (Playwright -- source of truth)
├── node recordings/scripts/wN-<short-name>.js  ⟶  recordings/har/wN-<short-name>.har
│      └── npx har-to-k6 wN-<short-name>.har    ⟶  tests/wN-<short-name>/from-har.js  (raw)
│            └── hand cleanup       ⟶  tests/wN-<short-name>/protocol.js  (final)
└── 5-step manual conversion        ⟶  tests/wN-<short-name>/browser.js   (final)
```

See the `k6-perf-test-website` skill references:
- `recording-with-playwright.md` for the recorder pattern
- `functional-tests.md` for the 5-step Playwright → k6/browser
  conversion

## Re-record when

- The app's bundled hash-named assets change (the protocol test
  will fail with a 404 — re-record to refresh the asset paths).
- The API or workflow changes the recorded request sequence.
- You want a fresh HAR for analysis (before/after a backend
  change).

```bash
# 1. Re-run the recorder
node recordings/scripts/wN-<short-name>.js

# 2. Regenerate raw k6
npx har-to-k6 recordings/har/wN-<short-name>.har -o tests/wN-<short-name>/from-har.js

# 3. By hand: bring new asset paths / request sequences into
#    tests/wN-<short-name>/protocol.js and tests/wN-<short-name>/browser.js.

# 4. Verify
./tests/run-all.sh
```

## Why HARs are committed

- Reproducibility — anyone reading the repo can see what was
  captured.
- Diff-ability — when the app is rebuilt, `git diff` shows what
  changed at the protocol layer.
- Small enough — typical HAR is 300 KB - 2 MB.

## Recorder template notes

- All recorders use `recordHar.urlFilter` to keep third-party
  collectors (RUM, error reporters, analytics, ads, social, …)
  out of the HAR. **Critical** — see skill gotchas.
- All recorders have a belt-and-braces `context.route` filter
  that aborts third-party requests at the network layer too.
- All recorders are headless by default
  (`chromium.launch({ headless: true })`).
- All recorders use a **real Chrome** UA, not the
  `HeadlessChrome` default. The default UA triggers bot-blocking
  on many production sites.
- All recorders are idempotent — re-running overwrites the HAR.
- `BASE_URL` can be overridden via env. The `urlFilter` regex
  must accept any host you use (default: target host + localhost).
