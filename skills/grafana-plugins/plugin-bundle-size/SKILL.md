---
name: plugin-bundle-size
license: Apache-2.0
description:
  Optimise Grafana app plugin bundle size using React.lazy, Suspense, and webpack code splitting.
  Use when the user asks to reduce plugin bundle size, optimise module.js, add code splitting,
  improve initial plugin load performance, split plugin chunks, lazy load plugin pages, or
  help implement lazy loading in a Grafana app plugin. Triggers on phrases like "optimise plugin
  bundle size", "module.js is too large", "plugin is slow to load", "code split the plugin",
  "reduce initial JS payload", or "help me with Suspense in my plugin".
---

# Grafana plugin bundle size optimisation

`module.js` is the render-blocking entry point for every Grafana app plugin. The smaller it is, the less impact the plugin has on Grafana's overall startup time. A well-split plugin should have a `module.js` under ~200 KB that contains nothing but lazy-loaded wrappers — all feature code loads on demand.

**Target:** ~15–25 JS chunks total. Fewer means too little splitting; far more (50+) means over-engineering.

## Risk levels

Not all splitting opportunities carry the same risk. Apply them in this order:

| Level | What | Risk | Impact |
|---|---|---|---|
| **Safe** | `module.tsx` lazy wrappers (Priority 1) | Very low — no behaviour change | Highest — module.js drops 90%+ |
| **Safe** | Route-level `lazy()` (Priority 2) | Low — each route is self-contained | High — one chunk per route |
| **Safe** | Extension `lazy()` (Priority 3) | Low — extensions are isolated | Medium — independent chunk per extension |
| **Moderate** | Component registries / tab panels (Priority 4) | Medium — verify Suspense placement | Medium — splits heavy pages further |
| **Do not touch** | Vendor libraries (`@grafana/scenes`, `@reduxjs/toolkit`) | N/A | N/A — webpack splits these automatically |
| **Do not touch** | Shared utility components (Markdown, Spinner) used across many files | High churn, many callsites | Low — already in shared vendor chunks |

When in doubt, stop after Priority 2. Routes alone typically reduce `module.js` by 95%+.

---

## Step 1: Add bundle size CI reporting (recommended)

Add the `grafana/plugin-actions/bundle-size` action to get automatic bundle size comparison comments on every PR. This posts a table showing entry point size changes, file count diffs, and total bundle impact.

**Root-level plugins** (plugin at repo root):

```yaml
# .github/workflows/bundle-size.yml
name: Bundle Size
on:
  pull_request:
  push:
    branches: [main]
  workflow_dispatch:

jobs:
  bundle-size:
    runs-on: ubuntu-latest
    permissions:
      contents: write
      id-token: write
      pull-requests: write
      actions: read
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version-file: .nvmrc
      - name: Install and build
        run: yarn install
      - name: Bundle Size
        uses: grafana/plugin-actions/bundle-size@a66a1c96cdbb176f9cccf10cf23593e250db7cce # bundle-size/v1.1.0
```

**Subdirectory plugins** (e.g. `plugin/` in a monorepo):

The action's install step runs at the repo root and cannot find `yarn.lock` in a subdirectory. Work around this by installing deps yourself and symlinking to root:

```yaml
jobs:
  bundle-size:
    runs-on: ubuntu-latest
    permissions:
      contents: write
      id-token: write
      pull-requests: write
      actions: read
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version-file: ./plugin/.nvmrc
      - name: Install dependencies
        working-directory: ./plugin
        run: yarn install
      - name: Symlink plugin to root for bundle-size action
        run: |
          ln -s plugin/yarn.lock yarn.lock
          ln -s plugin/package.json package.json
          ln -s plugin/.yarnrc.yml .yarnrc.yml
          ln -s plugin/node_modules node_modules
      - name: Bundle Size
        uses: grafana/plugin-actions/bundle-size@a66a1c96cdbb176f9cccf10cf23593e250db7cce # bundle-size/v1.1.0
        with:
          working-directory: ./plugin
```

**How it works:** On push to main, builds and uploads a baseline artifact. On PRs, compares against it and posts a diff comment. Use `workflow_dispatch` to generate the first baseline.

**Reference:** [grafana-k8s-plugin workflow](https://github.com/grafana/grafana-k8s-plugin/blob/main/.github/workflows/grafana.yml)

---

## Step 2: Detect plugin context

```bash
# Confirm this is an app plugin (type: "app" — datasource/panel plugins have different needs)
jq -r '"\(.id) — \(.type)"' src/plugin.json

# Locate the entry point
ls src/module.ts src/module.tsx 2>/dev/null

# Measure the current PRODUCTION bundle size BEFORE making any changes
# Dev builds are unminified and much larger — always measure production
yarn build 2>/dev/null || npm run build
echo "=== module.js ===" && ls -lah dist/module.js
echo "=== all JS chunks ===" && ls -lah dist/*.js | sort -k5 -rh | head -20
echo "=== chunk count ===" && ls dist/*.js | wc -l
```

Record the baseline. A pre-split plugin commonly has a `module.js` of 1–3 MB with no other JS chunks.

---

## Step 3: Check and update create-plugin

The `@grafana/create-plugin` tool controls `.config/webpack/`, `.config/jest/`, and other build scaffolding. Updating it often unlocks faster SWC compilation and better chunk output.

```bash
cat .config/.cprc.json 2>/dev/null || grep '"@grafana/create-plugin"' package.json
npm view @grafana/create-plugin version
npx @grafana/create-plugin@latest update
```

After updating, review the diff (especially `.config/webpack/webpack.config.ts`) and run a test build. If the plugin has a top-level `webpack.config.ts` that `webpack-merge`s the base config, review the merge for conflicts.

---

## Step 4: Analyse the codebase — find what to split

Do **not** start implementing until you have read all of these.

```bash
# Entry point — look for direct (non-lazy) imports of App, ConfigPage, exposeComponent targets
cat src/module.ts 2>/dev/null || cat src/module.tsx

# Root App component — look for direct page/route imports that should be lazy
cat src/App.tsx src/components/App.tsx src/feature/app/components/App.tsx 2>/dev/null | head -80

# Extension registrations — each should become an independent chunk
grep -r "exposeComponent\|addComponent\|addLink" src/ --include="*.ts" --include="*.tsx" -n

# Exported side-effect singletons (Faro, analytics) — must be extracted before splitting
grep -n "^export const\|^export let" src/module.ts src/module.tsx 2>/dev/null
grep -rn "from '.*module'" src/ --include="*.ts" --include="*.tsx" | grep -v node_modules

# Heavy synchronous imports
grep -rn "from 'monaco-editor\|@codemirror\|d3\b\|recharts\|chart\.js" \
  src/ --include="*.ts" --include="*.tsx" | grep -v node_modules
```

**Key rule:** If a file is imported by `module.ts` directly (even transitively), it ends up in `module.js`. Everything reachable from a lazy boundary becomes its own chunk.

---

## Step 5: Implement splits — in priority order

> **Named vs default exports:** `React.lazy()` requires a `default` export. Most Grafana plugin components use named exports — use `.then()` to re-map:
> ```ts
> // Named export
> const LazyMyComp = lazy(() => import('./MyComponent').then(m => ({ default: m.MyComponent })));
> // Default export
> const LazyMyComp = lazy(() => import('./MyComponent'));
> ```

### Priority 1: module.tsx (highest impact, always do this first)

If the entry point is `module.ts`, rename it: `git mv src/module.ts src/module.tsx`

Make `module.tsx` import **nothing** from feature code except through `lazy()`:

```tsx
import React, { lazy, Suspense } from 'react';
import { AppPlugin, AppRootProps } from '@grafana/data';
import { LoadingPlaceholder } from '@grafana/ui';

import type { MyExtensionProps } from './extensions/MyExtension';  // import type — erased at compile time
import type { JsonData } from './features/app/state/slice';

// Lazy Faro init — keeps @grafana/faro-react out of module.js
let faroInitialized = false;
async function initFaro() {
  if (faroInitialized) { return; }
  faroInitialized = true;
  const { initializeFaro } = await import('faro');
  initializeFaro();
}

const LazyApp = lazy(async () => {
  await initFaro();
  return import('./features/app/App').then(m => ({ default: m.App }));
});

function App(props: AppRootProps<JsonData>) {
  return <Suspense fallback={<LoadingPlaceholder text="" />}><LazyApp {...props} /></Suspense>;
}

const LazyMyExtension = lazy(() =>
  import('./extensions/MyExtension').then(m => ({ default: m.MyExtension }))
);
function MyExtension(props: MyExtensionProps) {
  return <Suspense fallback={<LoadingPlaceholder text="" />}><LazyMyExtension {...props} /></Suspense>;
}

export const plugin = new AppPlugin<JsonData>().setRootPage(App);
plugin.exposeComponent({ id: 'my-plugin/my-extension/v1', title: 'My Extension', component: MyExtension });
```

**Key details:**
- `import type` for props prevents webpack from following the import into the eager bundle
- Use `new AppPlugin<JsonData>()` if App uses `AppRootProps<JsonData>` — without the generic, `setRootPage()` type won't match
- Remove any `App as unknown as ComponentClass<AppRootProps>` cast — the lazy wrapper is a valid function component

**Expected impact:** `module.js` drops from MB range to ~50–200 KB.

**Singletons (e.g. Faro):** If `module.ts` has `export const faro = initializeFaro()`, do NOT keep it as a top-level import. Extract it to `src/faro.ts`, update all internal imports from `'*/module'` → `'*/faro'`, then use the dynamic `initFaro()` pattern above.

---

### Priority 2: Route-based splitting in App.tsx

```tsx
import React, { lazy, Suspense } from 'react';
import { Route, Routes } from 'react-router-dom';
import { LoadingPlaceholder } from '@grafana/ui';

const HomePage     = lazy(() => import('../pages/Home'));
const SettingsPage = lazy(() => import('../pages/Settings'));
const DetailPage   = lazy(() => import('../pages/Detail'));

function App(props: AppRootProps) {
  return (
    <Suspense fallback={<LoadingPlaceholder text="" />}>
      <Routes>
        <Route path="home"       element={<HomePage />} />
        <Route path="settings"   element={<SettingsPage />} />
        <Route path="detail/:id" element={<DetailPage />} />
        <Route path=""           element={<HomePage />} />
      </Routes>
    </Suspense>
  );
}
export default App;
```

**Bypass barrel files:** Target the actual component file in the `import()`, not an `index.ts` barrel that re-exports multiple things:

```tsx
// Risky — barrel may pull in other heavy modules
const Catalog = lazy(() => import('features/catalog'));
// Better — only pulls in Catalog's tree
const Catalog = lazy(() => import('features/catalog/Catalog').then(m => ({ default: m.Catalog })));
```

### Priority 3: Extension components

Each extension should `export default` its component. Use `fallback={null}` for extensions that load quickly:

```tsx
// src/extensions/MyExtension.tsx
export default function MyExtension(props: MyExtensionProps) {
  return <AppProviders><MyExtensionContent {...props} /></AppProviders>;
}
```

**Surgical split:** If an extension wrapper must stay eager in `module.tsx`, lazy-load the heavy component it renders:

```tsx
const HeavyInner = lazy(() => import('components/features/HeavyInner'));
export function MyExtension() {
  return <Suspense fallback={<LoadingPlaceholder text="" />}><HeavyInner /></Suspense>;
}
```

### Priority 4: Component registries and tab panels

For arrays of objects containing React components (e.g. tab panels), lazy-load each entry. **Critical:** ensure a `<Suspense>` boundary exists where the component renders.

```tsx
const ConfigDetails = lazy(() => import('./ConfigDetails/ConfigDetails').then(m => ({ default: m.ConfigDetails })));
const Overview      = lazy(() => import('./Overview/Overview').then(m => ({ default: m.Overview })));

const tabs = [
  { id: 'overview', component: Overview },
  { id: 'config',   component: ConfigDetails },
];

// In the parent that renders the active tab:
<Suspense fallback={<LoadingPlaceholder text="" />}>
  {ActiveTab && <ActiveTab />}
</Suspense>
```

For **datasource plugins** (`setConfigEditor`, `setQueryEditor`, `VariableSupport`, `AnnotationSupport`), see [references/datasource-plugins.md](references/datasource-plugins.md).

---

## Step 6: Group related chunks if over-splitting

If the build produces more than ~25 JS files, use webpack magic comments:

```tsx
const FleetList   = lazy(() => import(/* webpackChunkName: "fleet" */ '../pages/FleetList'));
const FleetDetail = lazy(() => import(/* webpackChunkName: "fleet" */ '../pages/FleetDetail'));
```

One `webpackChunkName` per logical feature area. Don't group unrelated pages.

---

## Step 7: Measure and verify

```bash
yarn build 2>/dev/null || npm run build
echo "=== module.js ===" && ls -lah dist/module.js
echo "=== all JS chunks (largest first) ===" && ls -lah dist/*.js | sort -k5 -rh | head -30
echo "=== chunk count ===" && ls dist/*.js | wc -l
```

| Metric | Target |
|---|---|
| `module.js` size | < 200 KB |
| Total JS chunk count | 15–25 |
| Largest single chunk | < 1 MB |

```bash
# Analyse bundle composition if a chunk is unexpectedly large
npx webpack-bundle-analyzer dist/stats.json 2>/dev/null
```

---

## Step 8: Test the running plugin

1. Open the plugin in a Grafana instance
2. Navigate to **every route** — each triggers a new chunk download
3. **DevTools → Network → JS**: confirm lazy chunks load on navigation, not all upfront
4. Check **Console** for errors
5. Test any `exposeComponent` extensions from other Grafana apps

For troubleshooting common issues, see [references/troubleshooting.md](references/troubleshooting.md).

---

## References

- [grafana-collector-app](https://github.com/grafana/grafana-collector-app) — app plugin reference implementation
- [grafana/plugin-actions](https://github.com/grafana/plugin-actions) — official Grafana plugin CI actions
- [Web.dev — code splitting with lazy and Suspense](https://web.dev/articles/code-splitting-suspense)
- [SurviveJS — webpack code splitting](https://survivejs.com/books/webpack/building/code-splitting/)
- [webpack magic comments](https://webpack.js.org/api/module-methods/#magic-comments)
