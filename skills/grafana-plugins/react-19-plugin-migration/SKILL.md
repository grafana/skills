---
name: react-19-plugin-migration
license: Apache-2.0
description:
  Migrate a Grafana plugin to React 19 compatibility. Use when the user asks to update a plugin
  for React 19, prepare for React 19, fix React 19 compatibility, upgrade to React 19, migrate
  to React 19, bump grafanaDependency to 12.3.0, externalize jsx-runtime, or run react-detect.
  Triggers on phrases like "update plugin for React 19", "React 19 migration", "prepare for
  React 19", "plugin React 19 compat", "grafanaDependency 12.3.0", "JSX runtime externals",
  "react-detect", "SECRET_INTERNALS", "ReactCurrentOwner", or "ReactCurrentDispatcher".
---

# Migrate Grafana Plugin to React 19

Grafana 13 (April 2026) moves from React 18 to React 19. Incompatible plugins will break.
**Do not upgrade React to 19** — only make forward-compatible changes.

All changes go in **one PR**. Execute steps in order. Never manually edit `yarn.lock`.

---

## Step 1: Detect plugin context

```bash
PLUGIN_JSON=$([ -f src/plugin.json ] && echo "src/plugin.json" \
  || ([ -f plugin/src/plugin.json ] && echo "plugin/src/plugin.json" || echo ""))
PKG_JSON=$([ -f package.json ] && echo "package.json" \
  || ([ -f plugin/package.json ] && echo "plugin/package.json" || echo ""))
PLUGIN_ID=$(jq -r '.id' $PLUGIN_JSON 2>/dev/null)
[ -f yarn.lock ] && PM="yarn" || ([ -f pnpm-lock.yaml ] && PM="pnpm" || PM="npm")
CP_VERSION=$(jq -r '.version' .config/.cprc.json 2>/dev/null)
echo "PLUGIN_ID=$PLUGIN_ID  PM=$PM  CP=$CP_VERSION"
```

If `PLUGIN_ID` is empty, ask the user for the plugin root path.

---

## Step 2: Scan for compatibility issues

Build the plugin and run the React 19 compatibility scanner:

```bash
npm run build 2>&1 | tail -5
npx -y @grafana/react-detect@latest 2>&1
```

Save the output. It flags:

- `jsxRuntimeImport` / `__SECRET_INTERNALS` → Step 4 fixes this
- `defaultProps` / `propTypes` / `ReactDOM.render` → Step 8 (source fixes)
- `findDOMNode` → Step 6 (dependency bump) or Step 8 (source fix)

If the build fails (plugin hasn't been built before), skip this step and run react-detect
after Step 9 instead. If output says "No breaking changes detected", still proceed — jsx-runtime
externalization and grafanaDependency bump are always required.

Re-run react-detect after Step 9 to confirm all issues are resolved.

---

## Step 3: Update `@grafana/create-plugin`

The scaffolding update brings in externals extraction, jest mocks, Docker fixes, and webpack
improvements needed for React 19. **Always do this before `add externalize-jsx-runtime`.**

Requires a clean git working tree. Create a feature branch first if not already on one.

### Run the update

```bash
npx @grafana/create-plugin@latest update 2>&1
```

### If `yarn install` fails with "engine is incompatible"

The update runs an intermediate `yarn install` without `--ignore-engines`. Complete it manually:

```bash
yarn install --ignore-scripts --ignore-engines 2>&1 | tail -10
```

Commit the intermediate state and re-run:

```bash
git add -A && git commit -m "chore: intermediate create-plugin update" --no-verify
npx @grafana/create-plugin@latest update 2>&1
```

### If ESLint 9 migration (004) fails with a parser error

The auto-migration can generate invalid JS on plugins with complex ESLint configs.
**Do not skip** — commit what succeeded, then complete the ESLint 9 migration manually:

```bash
git add -A && git commit -m "chore: update create-plugin (ESLint 9 migration manual)" --no-verify
```

Then follow the "Complete ESLint 9 migration" section below to finish.

### After the update

Always run install and verify:

```bash
yarn install --ignore-scripts --ignore-engines 2>&1 | tail -10
cat .config/.cprc.json
```

Commit if there are changes:

```bash
git add -A && git diff --cached --quiet || git commit -m "chore: update create-plugin scaffolding" --no-verify
```

---

## Step 3b: Complete ESLint 9 migration

The `create-plugin update` bumps ESLint to v9, which requires flat config (`eslint.config.js`)
instead of `.eslintrc`. Whether the auto-migration (004) succeeded, partially succeeded, or
failed, **you must ensure ESLint works before proceeding**.

### Check the current state

```bash
ls eslint.config.js .eslintrc* .config/.eslintrc* 2>/dev/null
npx eslint --version 2>&1
```

Three scenarios:

**A) `eslint.config.js` exists and `yarn lint` passes** — auto-migration succeeded. Proceed.

**B) `eslint.config.js` exists but `yarn lint` fails** — partial migration. Fix the issues:

```bash
yarn lint 2>&1 | head -30
```

Common fixes:
- `Invalid option '--ignore-path'` or `Invalid option '--ext'` → remove those flags from
  the `lint` script in `package.json`. In ESLint v9 flat config, ignores and file matching
  are configured inside `eslint.config.js`, not via CLI flags. Update to: `eslint --cache .`
- `Cannot find module 'eslint-plugin-deprecation'` → remove the import/reference from
  `eslint.config.js` (replaced by `@typescript-eslint/no-deprecated`)
- Other dead plugin imports → remove them from the config if the package was removed

**C) No `eslint.config.js` exists** — auto-migration failed. Create one manually:

```bash
ls node_modules/@grafana/eslint-config/flat.js 2>/dev/null
```

If `flat.js` exists, create `eslint.config.js` using it as the base:

```js
import grafanaConfig from '@grafana/eslint-config/flat';

export default [
  ...grafanaConfig,
  {
    ignores: ['**/dist/', '**/node_modules/', '**/.config/', '**/coverage/'],
  },
];
```

Then migrate any custom rules from the old `.eslintrc` into additional config objects in the array.
After creating the flat config:

1. Update the `lint` script: `"lint": "eslint --cache ."`
2. Delete the root `.eslintrc` (leave `.config/.eslintrc` — it's scaffolded and harmless)

### Verify lint works

```bash
yarn lint 2>&1 | tail -20
```

Fix auto-fixable issues with `yarn lint --fix`. Commit:

```bash
git add -A && git diff --cached --quiet || git commit -m "chore: complete ESLint 9 flat config migration" --no-verify
```

---

## Step 4: Externalize jsx-runtime

**Always use the `create-plugin add` command.** Requires a clean git working tree.

```bash
npx @grafana/create-plugin@latest add externalize-jsx-runtime 2>&1
```

Verify:

```bash
grep "jsx-runtime" .config/bundler/externals.ts 2>/dev/null
```

- Found → commit and proceed.
- Not found → command failed. **Only then** add externals manually to the root `webpack.config.ts`:

```ts
externals: ['react/jsx-runtime', 'react/jsx-dev-runtime'],
```

Commit:

```bash
git add -A && git diff --cached --quiet || git commit -m "feat: externalize jsx-runtime" --no-verify
```

---

## Step 5: Bump `grafanaDependency`

```bash
jq -r '.dependencies.grafanaDependency' $PLUGIN_JSON
```

If not already `>=12.3.0`, update it. The `create-plugin add` in Step 3 may have already done this.

---

## Step 6: Bump dependencies

### Faro (if present)

```bash
grep '"@grafana/faro' $PKG_JSON
```

| Package | Target |
|---------|--------|
| `@grafana/faro-react` | `^2.2.3` |
| `@grafana/faro-web-sdk` | `^2.2.3` |
| `@grafana/faro-web-tracing` | `^2.0.0` |

### Grafana packages

```bash
grep '"@grafana/' $PKG_JSON | grep -v faro | grep -v create-plugin
```

Bump `@grafana/data`, `@grafana/runtime`, `@grafana/schema`, `@grafana/ui` to `^12.2.0` or later.
Add `@grafana/i18n@^12.2.0` if the plugin uses translations or `@grafana/scenes` requires it.

### React types

Bump `react` and `react-dom` to `^18.3.0` (surfaces React 19 issues early).
Add `@types/react@^18.3.0` and `@types/react-dom@^18.3.0` to devDependencies if missing.

### Remove deprecated packages

Remove from devDependencies if present:
- `eslint-plugin-deprecation` (replaced by `@typescript-eslint/no-deprecated`)
- `@types/testing-library__jest-dom` (replaced by `setupTests.d.ts`)

### Broken transitive dependencies

If `yarn install` fails with a stale git reference, **do not edit yarn.lock**. Add a `resolutions` entry:

```json
"resolutions": {
  "<package-name>": "<working-version-or-git-ref>"
}
```

Then delete `yarn.lock` and `node_modules` and reinstall:

```bash
rm -rf node_modules yarn.lock
yarn install --ignore-engines 2>&1 | tail -10
```

---

## Step 7: Fix unmet `@openfeature/web-sdk` peer dependency

`@grafana/runtime` depends on `@openfeature/react-sdk` which has `@openfeature/web-sdk` as a
**peer dependency**. Yarn v1 (classic) does not auto-install peer deps.

Check if the plugin uses yarn classic:

```bash
yarn --version 2>&1 | head -1
```

If version starts with `1.`, check for warnings:

```bash
yarn install --ignore-engines 2>&1 | grep "unmet peer dependency.*openfeature/web-sdk"
```

If warnings are found:

```bash
yarn add -D @openfeature/web-sdk @openfeature/core --ignore-engines
```

**Skip condition:** Yarn v2+ or npm v7+ (peer deps are auto-installed).

---

## Step 8: Fix source code issues

```bash
grep -rn "ReactDOM\.render\|ReactDOM\.unmountComponentAtNode\|ReactDOM\.findDOMNode" src/ --include="*.tsx" --include="*.ts"
grep -rn "\.defaultProps\s*=" src/ --include="*.tsx" --include="*.ts"
grep -rn "\.propTypes\s*=" src/ --include="*.tsx" --include="*.ts"
grep -rn "contextTypes\|getChildContext" src/ --include="*.tsx" --include="*.ts"
grep -rn "createFactory" src/ --include="*.tsx" --include="*.ts"
grep -rn "ChangeEvent<HTMLInputElement>" src/ --include="*.tsx" --include="*.ts"
```

| Pattern | Fix |
|---------|-----|
| `ReactDOM.render()` | `createRoot(container).render(element)` |
| `defaultProps` on **function** components | Move to destructured parameter defaults |
| `defaultProps` on **class** components | Leave — still works |
| `propTypes` | Remove |
| `contextTypes` / `getChildContext` | Use `React.createContext()` + `useContext()` |
| `createFactory` | Use JSX or `createElement()` |
| `ChangeEvent<HTMLInputElement>` on checkbox | Change to `FormEvent<HTMLInputElement>` |

---

## Step 9: Build, typecheck, test

```bash
rm -rf node_modules dist
yarn install --ignore-engines 2>&1 | tail -10
yarn build 2>&1 | tail -10
yarn typecheck 2>&1 | tail -10
yarn test --watchAll=false 2>&1 | tail -10
```

| Error | Fix |
|-------|-----|
| `Cannot find module 'react/jsx-runtime'` | Step 4 not applied — re-run `create-plugin add` |
| `Cannot find module '@openfeature/web-sdk'` | Step 7 — `yarn add -D @openfeature/web-sdk @openfeature/core` |
| `Can't resolve '@grafana/i18n'` | `yarn add @grafana/i18n@^12.2.0` |
| `Cannot read properties of undefined (reading 'ReactCurrentOwner')` | Bump `@grafana-cloud/*` packages — see Step 6 |
| `aria-label is missing` on icon-only `Button` | Add `aria-label` prop (newer `@grafana/ui` requires it) |
| Stale git hash in `yarn.lock` | Add `resolutions` in `package.json`, delete lockfile, reinstall |

For detailed known issues (i18n crash, `@grafana/schema` type breaks, publicPath mismatch), see
[references/known-issues.md](references/known-issues.md).

---

## Step 10: Update CI (if applicable)

```bash
grep -rn "plugin-ci-workflows\|e2e-version" .github/workflows/ 2>/dev/null
```

- `plugin-ci-workflows@main` or >= 6.0.0 → already tests React 19. No changes needed.
- `plugin-actions/e2e-version` → add `skip-grafana-react-19-preview-image: false`.
- Neither found → test manually with `GRAFANA_VERSION=dev-preview-react19 docker compose up --build`.

---

## Step 11: Squash and push

```bash
git reset --soft origin/main
git add -A
git commit -m "fix: Prepare plugin for React 19 compatibility"
```

Commit message body should list: create-plugin version change, ESLint 9 migration, key dependency
bumps, and any source code fixes.

---

## References

- [Migration guide](https://grafana.com/developers/plugin-tools/migration-guides/update-from-grafana-versions/migrate-12_x-to-13_x)
- [React 19 blog post for plugin developers](https://grafana.com/blog/react-19-is-coming-to-grafana-what-plugin-developers-need-to-know/)
- [React 19 changelog](https://react.dev/blog/2024/12/05/react-19)
- [grafana-collector-app #1337](https://github.com/grafana/grafana-collector-app/pull/1337) — full migration with create-plugin update + source fixes
- [grafana/scenes issues](https://github.com/grafana/scenes/issues) — upstream i18n tracking
