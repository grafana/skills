# Known Issues: React 19 Plugin Migration

## `ReactCurrentOwner` / `ReactCurrentDispatcher` crash from `@grafana-cloud` packages

Plugins using `@grafana-cloud/*` packages may crash immediately on load with:

```
TypeError: Cannot read properties of undefined (reading 'ReactCurrentOwner')
```

or:

```
TypeError: Cannot read properties of undefined (reading 'ReactCurrentDispatcher')
```

**Root cause:** Older `@grafana-cloud` package builds did not externalize `react/jsx-runtime`.
Webpack bundled a copy of `react/jsx-runtime` from React 18 into each package's UMD output.
At runtime with React 19, the bundled shim accesses
`React.__SECRET_INTERNALS_DO_NOT_USE_OR_YOU_WILL_BE_FIRED.ReactCurrentOwner` (or
`ReactCurrentDispatcher`), which no longer exists in React 19.

**Fix:** Bump all `@grafana-cloud/*` dependencies to versions that include the jsx-runtime fix.
Check each package's changelog for the version that adds `externalize-jsx-runtime`.

Minimum versions (check your registry for the latest):

| Package | Minimum version |
|---------|----------------|
| `@grafana-cloud/access-policies` | `3.12.0` |
| `@grafana-cloud/activation-api` | `3.9.0` |
| `@grafana-cloud/alloy-configurator` | `2.3.0` |
| `@grafana-cloud/asserts-ui` | `3.8.0` |
| `@grafana-cloud/collector` | `3.12.0` |
| `@grafana-cloud/fleet-management-api` | `3.12.0` |
| `@grafana-cloud/grafana-api` | `3.8.0` |
| `@grafana-cloud/grafana-com-api` | `3.9.0` |
| `@grafana-cloud/integrations-api` | `3.8.0` |
| `@grafana-cloud/ui` | `3.10.0` |

---

## `t() was called before i18n was initialized` (plugins using `@grafana/scenes`)

Plugins using `@grafana/scenes` >= 6.38 may crash in dev mode with:

```
t() was called before i18n was initialized. Make sure to call initPluginTranslations()
```

**Root cause:** `@grafana/i18n` is not in the plugin externals or Grafana's `sharedDependenciesMap`,
so webpack bundles a separate copy with its own uninitialized `tFunc`.

Check if affected:

```bash
grep -rn "@grafana/scenes" $PKG_JSON
```

**Workaround A: Explicit initialization** — call `initPluginTranslations` with scenes'
`loadResources` before the app renders (e.g. in `module.tsx`):

```ts
import { initPluginTranslations } from '@grafana/i18n';
import { loadResources } from '@grafana/scenes';

await initPluginTranslations('grafana-scenes', [loadResources]);
```

**Workaround B: Webpack alias** — deduplicate `@grafana/i18n` copies:

```ts
import path from 'path';

// Inside the merge config:
resolve: {
  alias: {
    '@grafana/i18n': path.resolve(process.cwd(), 'node_modules/@grafana/i18n'),
  },
},
```

**Workaround C: Patch dev-mode throw** — if A and B don't resolve it:

```bash
yarn add -D string-replace-loader
```

```ts
module: {
  rules: [
    {
      test: /node_modules\/@grafana\/i18n/,
      loader: 'string-replace-loader',
      options: {
        search: "throw new Error\\('t\\(\\) was called before i18n was initialized",
        replace: "tFunc = getI18nInstance().t; // patched: use production fallback in dev",
        flags: '',
      },
    },
  ],
},
```

Tracking issue: [grafana/scenes #1322](https://github.com/grafana/scenes/issues/1322)

---

## Type errors from `@grafana/schema` 12.4.0

`^12.2.0` resolves to 12.4.0 which introduced breaking type changes:
- `footer` removed from table panel `Options` type (moved to `TableFieldOptions`)
- `hidden` removed from `TableFieldOptions` (use `hideFrom: { legend: true, tooltip: true, viz: true }`)
- `React.ComponentProps<typeof Button>` can no longer be extended with `interface extends` (use type intersection)

If the plugin uses table panel types from `@grafana/schema`, pin to avoid the break:

```json
"resolutions": {
  "@grafana/schema": "12.3.4"
}
```

---

## `react/jsx-runtime` 404 at runtime

The externalized `react/jsx-runtime` requires Grafana >= 12.3.0 to provide it via SystemJS.
Verify the docker-compose default is >= 12.3.0:

```bash
grep "grafana_version" .config/docker-compose-base.yaml docker-compose.yaml 2>/dev/null
```

If it shows a version < 12.3.0, bump it.

---

## ESLint `import/no-unused-modules` error in flat config

In ESLint flat config, `eslint-plugin-import`'s `no-unused-modules` rule can error. If this
affects the plugin, keep a minimal `.eslintrc` with only `ignorePatterns` (known limitation).

---

## Chunks cache forever after webpack alias change

If adding a webpack resolve alias, ensure `output.chunkFilename` includes `[contenthash]` so
users receive updated chunks after deploy.

---

## Dev build sizes are huge

Always measure with a **production build**, not dev:

```bash
rm -rf dist node_modules/.cache
yarn build --env production
```
