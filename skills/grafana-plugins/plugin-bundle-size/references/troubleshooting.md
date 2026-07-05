# Troubleshooting: Plugin Bundle Size

| Symptom | Cause | Fix |
|---|---|---|
| `module.js` barely shrank | Entry point still transitively imports feature code | Read `module.tsx` carefully — any direct import pulls its entire tree in |
| Route shows blank page | Component is rendered outside its Suspense boundary | Add `<Suspense>` wrapping in the parent, or move the boundary up |
| Extension crashes | Missing `AppProviders` context | Wrap the default export in the extension file with `<AppProviders>` |
| Too many chunks (50+) | Every subcomponent split | Use `webpackChunkName` to group related pages |
| `module.js` barely shrank after rename | Entry point re-exports a singleton (`faro`, analytics) that pulls in its whole init tree | Extract singleton to `src/faro.ts`; `module.tsx` re-exports it with `export { faro } from './faro'` |
| Circular dependency warning after split | Feature files import from `module.ts` (e.g. `faro`) and module.tsx lazy-imports them back | Extract the exported value to a dedicated file (see singleton note in the main skill) |
| Build fails after rename | `swc-loader` or `ts-loader` needs tsx support | Ensure `tsconfig.json` has `"jsx": "react-jsx"` and `"tsx"` in the parser config |
| `lazy()` throws "does not provide an export named 'default'" | Component uses a named export, not a default export | Use `.then(m => ({ default: m.ComponentName }))` |
| Datasource editor blank after split | Suspense missing on `VariableSupport.editor` or `AnnotationSupport.QueryEditor` | Wrap the assigned component with a Suspense boundary (see [datasource-plugins.md](datasource-plugins.md)) |
| `React.lazy` not available | Very old React or CommonJS module output | Requires React ≥ 16.6 and `esModuleInterop: true` in tsconfig |
| Chunks not loading in prod | `output.publicPath` mismatch | Verify `publicPath` in webpack config matches `public/plugins/<PLUGIN_ID>/` |
| ESLint `import/no-unused-modules` error after rename | `ignoreExports` glob only matches `.ts`, not `.tsx` | Add `'./src/*.tsx'` to `ignoreExports` in eslint config |
| Chunks cache forever after deploy | `chunkFilename` missing content hash | Add `[contenthash]` to `output.chunkFilename` in webpack config |
| `setRootPage()` type error after adding `JsonData` generic | `AppPlugin` not parameterised | Use `new AppPlugin<JsonData>()` so `setRootPage()` expects `AppRootProps<JsonData>` |
| Dev build sizes are huge (multi-MB) | Measuring dev instead of production | Always clean (`rm -rf dist node_modules/.cache`) and build with `--env production` for measurements |

> **rspack compatibility:** All `React.lazy()` / dynamic import patterns work identically with rspack.
> `webpackChunkName` magic comments are also supported. If the plugin uses `.config/rspack/`, no changes
> are needed to the build config.
