# Recording with Playwright

Per workflow, you produce one Playwright recorder
(`recordings/scripts/wN-<short-name>.js`) that captures a HAR. The HAR is then
converted to a k6 protocol script via `har-to-k6`.

## Recorder template anatomy

The bundled template has four critical parts:

### 1. Headless Chromium with a real Chrome UA

```js
const browser = await chromium.launch({ headless: true });
const context = await browser.newContext({
  userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) ' +
    'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36',
  recordHar: { /* see below */ },
});
```

**Why a real UA:** the default headless UA includes the string
`HeadlessChrome`, which triggers bot-blocking on many production
sites. Set a real Chrome UA on both the recorder (`userAgent` in
`browserContext`) and the k6 scripts (`options.userAgent`).

### 2. `recordHar.urlFilter` — the critical regex

```js
recordHar: {
  path: HAR_PATH,
  mode: 'full',
  content: 'embed',
  urlFilter: /^https?:\/\/(target-host\.example|localhost)(:\d+)?\//,
},
```

**Why:** third-party traffic from the target site (RUM agents,
error reporters, ad networks, analytics, …) pollutes:

- the recorded request count (inflating k6's apparent load),
- per-endpoint thresholds (third-party endpoints have no relation
  to your SLOs),
- the HAR file size (10-100× bloat is common).

`urlFilter` accepts a regex or string. **Always use a regex** that
allow-lists the target host(s) only.

### 3. Belt-and-braces `context.route`

```js
await context.route('**', (route) => {
  if (isAllowedHost(route.request().url())) return route.continue();
  return route.abort();
});
```

`recordHar.urlFilter` filters at HAR-write time but the browser
still **sends** the requests. The `context.route` filter aborts at
the network layer so:

- The third party doesn't get test traffic (politeness, and avoids
  polluting their dashboards).
- Bandwidth during recording is minimised.

Both filters are needed. `route.abort` alone leaves `status: -1`
entries in the HAR (har-to-k6 then generates broken k6 code).

### 4. Hydration-signal wait

Single-page apps render some markup before client JS hydrates and
attaches event handlers. If your recorder clicks a button before
hydration, the click does nothing.

```js
await page.goto(BASE_URL, { waitUntil: 'load' });

// Wait for the post-hydration sentinel. Pick a selector that ONLY
// exists once the SPA has booted — typically an interactive element
// (button, link) that is rendered by the framework, not the SSR.
const sentinel = page.locator('button[name="primary-action"]');
await sentinel.waitFor({ state: 'visible' });
```

`waitUntil: 'load'` is necessary but not sufficient — the DOM is
ready before JS has wired up handlers. The sentinel locator
guarantees hydration completed.

## The full recording pipeline

```
recordings/scripts/wN-<short-name>.js          (Playwright -- source of truth)
├── node recordings/scripts/wN-<short-name>.js  ⟶  recordings/har/wN-<short-name>.har
│      └── npx har-to-k6 wN-<short-name>.har    ⟶  tests/wN-<short-name>/from-har.js  (raw)
│            └── hand cleanup       ⟶  tests/wN-<short-name>/protocol.js  (final)
└── 5-step manual conversion        ⟶  tests/wN-<short-name>/browser.js   (final)
```

The 5-step manual conversion is in
`references/functional-tests.md`.

## How to spot a polluted HAR

After `node recordings/scripts/wN-<short-name>.js`:

```bash
# Count entries by host
jq '.log.entries | map(.request.url) | group_by(. | capture("//(?<h>[^/:]+)").h) | map({host: .[0] | capture("//(?<h>[^/:]+)").h, count: length})' recordings/har/wN-<short-name>.har
```

If you see any host other than your allow-listed target, the
`urlFilter` regex needs widening or tightening.

## How to spot missing hydration

After `npx har-to-k6 ... -o from-har.js`, run the script once:

```bash
k6 run --vus 1 --iterations 1 tests/wN-<short-name>/from-har.js
```

If you see the homepage in the request list but **none** of the
subsequent API calls fired by client JS, the recorder clicked
before hydration. Add a wait on a post-hydration sentinel and
re-record.

## Re-recording when the app changes

Re-record when:

- The bundled hash-named static assets change paths (e.g. SvelteKit
  rebuilds change `/_app/immutable/nodes/4.<hash>.js`). The
  protocol test will fail with a 404 on the asset, which is the
  intended signal.
- The API or workflow changes the recorded sequence of requests.
- You want a fresh HAR for analysis (e.g. comparing before/after a
  backend change).

```bash
# 1. Re-run the recorder
node recordings/scripts/wN-<short-name>.js

# 2. Regenerate the raw k6 script
npx har-to-k6 recordings/har/wN-<short-name>.har -o tests/wN-<short-name>/from-har.js

# 3. By hand: bring any new asset paths or request sequences into
#    tests/wN-<short-name>/protocol.js.

# 4. Verify
./tests/run-all.sh
```

## Why HARs are committed to git

- Reproducibility: anyone reading the repo sees what was captured.
- Diff-ability: when the app is rebuilt, `git diff` on the HAR
  shows what changed at the protocol layer.
- Small enough: typical HAR is 300 KB - 2 MB; usually fine to
  commit. If your app produces > 10 MB HARs, narrow the
  `urlFilter` further (you're probably capturing CDN assets you
  don't need).

## Tool preference

If `mcp-k6` is configured, prefer its Playwright capture and
Playwright→k6/browser migration tools. They handle:

- Real UA selection.
- Hydration-wait scaffolding.
- Selector extraction.

This skill's hand-written approach is the **fallback** when
`mcp-k6` isn't available, and the **specification** for what
`mcp-k6`'s output should resemble.
