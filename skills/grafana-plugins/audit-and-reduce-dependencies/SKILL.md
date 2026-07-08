---
name: audit-and-reduce-dependencies
license: Apache-2.0
description: >-
  Reduces JavaScript dependency footprint with pnpm while preserving lockfile,
  workspace layout, and dependency range style. Runs /check-npm first, then
  removes unused deps, dedupes versions, ranks transitive closure, and reports
  Keep/Replace/Remove triage. Use when cleaning up pnpm dependencies, reducing
  lockfile size, or shrinking node_modules in Grafana plugins; not for Go
  modules or full GitHub Actions workflow audits.
---

# Audit and reduce dependencies

Reduce JavaScript dependency footprint. Use **pnpm only**. Preserve the lockfile, workspace layout, and dependency range style unless there is a concrete reason to change them.

For GitHub Actions workflow triage (action choice, permissions, pinning), use a dedicated workflow audit — not the reporting format below (workflow file + step only when the finding is **pnpm install policy**).

## Workflow

0. Hardening gate: run `/check-npm` (read-only). See [check-npm](../check-npm/SKILL.md).
1. Establish the baseline.
2. Remove unused direct dependencies.
3. Deduplicate direct dependency versions in monorepos.
4. Rank direct dependencies by transitive lockfile closure.
5. Use closure data to find low-risk minor/patch upgrades.
6. Use closure data to find trivial dependencies worth inlining.
7. Check e18e recommendations for replacements/removals.
8. Reinstall, verify, and report measured impact.

## Step 0: Hardening gate (`/check-npm`)

Run **`/check-npm`** before mutating manifests or lockfiles.

- If any check **FAIL**s: report the table and fix snippets; **do not weaken** `pnpm-workspace.yaml`, `.npmrc`, CI install flags, or Renovate age gates during cleanup.
- Do not paste full hardening config into this workflow — `/check-npm` owns version thresholds, script policy, git-dep protocols, and min release age.
- If the user only asked for hardening (not reduction), stop after `/check-npm` unless they also want cleanup.

**pnpm 11+:** script and release-age policy live in `pnpm-workspace.yaml`, not `.npmrc` or `package.json#pnpm` (pnpm 11 no longer reads the `package.json#pnpm` field). Verify each key against the installed pnpm major before suggesting config. Never add unsupported keys. Do not lower an existing `minimumReleaseAge` (or org equivalent) during cleanup.

## Dependency triage

For each non-trivial direct dependency (especially after Steps 4–7), assign one label:

| Label | Meaning |
|-------|---------|
| **Keep** | Required; worthwhile transitive cost; well maintained. |
| **Replace-with-Better** | Required; better-maintained or safer alternative exists. |
| **Replace-with-Internal** | Required; external risk warrants internal implementation. |
| **Remove** | Can drop or inline (Step 6). |
| **Needs-user-review** | Ambiguous usage, policy tradeoff, or change needing human verification. |

**Replacements and new direct deps**

- **No new direct dependencies** (including swaps) without explicit user approval.
- Prefer **Remove** (inline/native APIs) over **Replace-with-Better** when equivalent.
- For **Replace-with-Better**: state why (maintenance, security, smaller tree); prefer actively maintained, widely adopted packages from trusted maintainers.
- Respect repo `minimumReleaseAge` / Renovate gates; command-level 72h freshness is a floor, not permission to bypass stricter config.

## pnpm & supply-chain

Confirm the repo uses pnpm: `pnpm-lock.yaml`, `pnpm-workspace.yaml`, and/or `packageManager` / `devEngines.packageManager.name` set to `pnpm` in root `package.json`. If not on pnpm, stop — do not migrate package managers as part of cleanup.

Respect repo install policy when present (e.g. `pnpm install --frozen-lockfile --ignore-scripts`).

| Action | Command |
|--------|---------|
| Install/update lockfile | `pnpm install --ignore-scripts` (+ repo flags, e.g. `--frozen-lockfile`) |
| Remove direct dependency | `pnpm remove <pkg> --ignore-scripts` |
| Add/update direct dependency | `pnpm add <pkg>@<version> --ignore-scripts` |
| Explain dependency | `pnpm why <pkg>` |
| Dedupe lockfile | `pnpm dedupe` (then `pnpm install --ignore-scripts` if lockfile changed) |
| Outdated / version info | `pnpm outdated <pkg>` |
| One-off tools | `pnpm --config.ignore-scripts=true dlx <pkg>@<version> <args...>` (pin version; prefer `pnpm exec` when in lockfile) |

**Lifecycle scripts:** Always `--ignore-scripts` on `pnpm install`, `pnpm add`, and `pnpm remove` unless the user explicitly writes **allow scripts** in the same message (state which scripts would run and the risk). For `pnpm dlx`, `dlx` does not accept `--ignore-scripts` directly — use `pnpm --config.ignore-scripts=true dlx` (flags after `dlx` are forwarded to the executed binary). If a dependency legitimately needs a build script (native modules, etc.), finish without scripts, then ask whether to run a **specific** manual rebuild (e.g. `pnpm rebuild <pkg>`).

**Freshness check (≥ 72 hours)** — required before any command that adds or upgrades a **named package version** (`pnpm add`, `pnpm dlx` with new/upgraded direct version). **Not required** for plain `pnpm install` / `pnpm remove` with no new package argument.

For each directly named package:

1. `curl -s https://registry.npmjs.org/<package-name>`
2. Resolve version: pinned `pkg@1.2.3` → that version; range/`latest`/unspecified → `dist-tags.latest`
3. Read `time["<version>"]`
4. If published **less than 72 hours ago** → **stop**. Tell the user package, version, and exact age. Suggest an older known-good pin unless they write **override freshness check**.
5. **`@grafana/*`** scoped packages are **exempt** from the freshness check; `--ignore-scripts` still applies.

After a failed freshness check, do not substitute a different version without user approval.

## Safety rules

- Work in small batches so lockfile diffs remain reviewable.
- Never trust unused-dependency tools blindly; verify imports, config files, scripts, generated code hooks, framework conventions, plugin names, CLIs, and dynamic imports.
- You may write scripting and parsing to verify `package.json` and lockfile dependency accounts.
- Treat `peerDependencies`, `optionalDependencies`, package bin usage, test fixtures, and published package manifests as higher risk.
- Do not remove or inline dependencies used for security, parsing, crypto, Unicode, URL handling, date/time, i18n, or platform compatibility unless the replacement is proven equivalent.
- Do not switch package managers, delete `pnpm-lock.yaml`, or rewrite workspace structure as part of cleanup.
- Treat `pnpm dedupe` as potentially behavior-changing; inspect lockfile diffs and run focused verification before keeping the result.
- Measure before and after: direct dependency count, lockfile line count or entry count, package count, and estimated `node_modules` size when available.

## Step 1: Baseline

Collect:

- All `package.json` files and workspace boundaries (`pnpm-workspace.yaml`).
- `pnpm-lock.yaml`, `pnpm-workspace.yaml` security settings (`minimumReleaseAge`, `strictDepBuilds`, `blockExoticSubdeps`, `allowBuilds`), and install policy in `.npmrc` / CI flags (e.g. `--frozen-lockfile`, `--ignore-scripts`).
- Direct dependency names by manifest section: `dependencies`, `devDependencies`, `peerDependencies`, `optionalDependencies`.
- Existing verification commands from scripts, CI, or repo docs.
- **CI spot-check** (`.github/workflows` or equivalent): installs should use `pnpm install --frozen-lockfile` and script blocking consistent with workspace config. Flag workflows that regenerate lockfiles on every run.
- **Renovate / Dependabot** (if present): note `minimumReleaseAge` for npm packages; do not reduce it during cleanup.

Record baseline metrics: `git status --short`, `wc -l pnpm-lock.yaml`. If `node_modules` is installed, estimate footprint with platform-appropriate tools. Lockfile reductions are the primary metric — do not depend on `node_modules` being present.

## Step 2: Remove unused direct dependencies

**Unsafe direct dependency protocols** — scan all workspace `package.json` dependency sections. Flag values that are not: semver range, `workspace:`, `patch:`, or `npm:` alias to semver. Flag `git:` / `github:` / tarball URLs / `user/repo` shorthand / `file:` / `link:` / `exec:` / etc. (same allow-list as `/check-npm`). Do not remove flagged entries silently; report for a separate hardening PR unless the user asked to fix them.

Use a static analyzer as a starting point, not as proof (knip, depcheck, or repo-native tooling). Run with pinned `pnpm --config.ignore-scripts=true dlx <tool>@<version> <args...>` when not installed (freshness-check the pin first).

For each candidate:

- Search code, configs, package scripts, build tooling, tests, and docs for the package name and known import paths.
- Check whether required by a published package manifest, peer contract, plugin loader, CLI command, or dynamic `require`/`import`.
- Remove only when no real usage remains.
- Run `pnpm install --ignore-scripts` (+ repo flags) and focused verification.

If usage is only in a script or config, consider moving between `dependencies` and `devDependencies` instead of removing.

## Step 3: Deduplicate monorepo direct versions

Look for the same direct dependency declared with multiple versions/ranges across package manifests. Use existing policy first: exact pins, caret ranges, catalog/protocol usage, workspace protocol, or central constraints.

- Use `syncpack list-mismatches` or equivalent for discovery.
- Standardize direct ranges when packages can share the same compatible version.
- Prefer manifest-level consistency before adding `pnpm.overrides`.
- Use `pnpm.overrides` only for transitive convergence or security fixes, and document why.

After deduping, run `pnpm install --ignore-scripts` (+ repo flags) and inspect manifest and lockfile diffs. Then consider `pnpm dedupe` — apply carefully; may change transitive resolution.

## Step 4: Rank transitive lockfile closure

For each important direct dependency, estimate closure: transitive lockfile entries reachable from that dependency.

Report both:

- **Total closure**: all packages reachable from the dependency.
- **Exclusive closure**: packages that disappear if this dependency is removed and are not retained by other direct dependencies.

Prefer deterministic measurement:

1. Save baseline lockfile metrics.
2. Temporarily remove one direct dependency from the owning manifest.
3. Run `pnpm install --ignore-scripts` (+ repo flags).
4. Measure lockfile line/entry reduction and package count reduction.
5. Revert the manifest *and* `pnpm-lock.yaml` (e.g., `git checkout -- <manifest> pnpm-lock.yaml`) before measuring the next dependency.

Use `pnpm why <pkg>` for large transitive packages. Rank by impact and risk, not just raw size.

## Step 5: Find low-risk high-impact upgrades

Use closure rankings to target direct dependencies whose newer minor/patch versions reduce transitive dependencies.

For each candidate:

- Check available non-major versions with `pnpm outdated`.
- Review changelog/release notes for dependency tree changes.
- Freshness-check the target version, then upgrade one dependency or tight cluster at a time (`pnpm add <pkg>@<version> --ignore-scripts`).
- Run `pnpm install --ignore-scripts` (+ repo flags) and compare closure metrics.
- Run focused tests and relevant build/typecheck commands.

Avoid major upgrades unless the user explicitly accepts the migration risk.

## Step 6: Inline trivial usage

Use closure rankings to find direct dependencies with small, obvious usage but large transitive cost.

Inline only when all are true:

- Usage is tiny and easy to fully characterize.
- Equivalent code is shorter or clearer than retaining the dependency.
- Behavior is covered by tests or can be covered with small characterization tests.
- The dependency is not solving cross-platform, security, parsing, Unicode, locale, or spec-compliance edge cases.

Prefer native APIs over new replacement dependencies when the required behavior is simple.

## Step 7: Apply e18e guidance

```bash
# Pin @e18e/cli@<version> after freshness check; disable scripts on the dlx install
pnpm --config.ignore-scripts=true dlx @e18e/cli@<version> analyze
pnpm --config.ignore-scripts=true dlx @e18e/cli@<version> migrate --dry-run
```

Also check https://e18e.dev/docs/replacements/. Treat recommendations as candidates, not mandates; verify bundle/runtime behavior and run tests. Map e18e swaps to **Replace-with-Better** only after user approval.

## Reporting

Summarize outcomes with measured impact:

- `/check-npm` result (PASS/FAIL summary; link fixes if FAIL).
- Direct dependencies removed or moved.
- Direct versions deduplicated.
- Lockfile line/entry reduction.
- Estimated package or `node_modules` reduction when available.
- High-impact candidates deferred and why (including replacements awaiting approval).
- Unsafe protocol / CI / Renovate findings from baseline (if any).
- Verification commands run and results.
- Supply-chain: versions freshness-checked (or exempted), `--ignore-scripts` on all installs/adds, `--config.ignore-scripts=true` on `pnpm dlx`.

Call out risk explicitly when a removal depends on static analysis rather than runtime coverage.

### Reporting format

Use for **dependency cleanup findings only** — not GitHub Actions workflow triage.

For each finding:

- **Evidence**: package name and version/range; manifest path and section; supporting signal (import site, `pnpm why`, knip/depcheck hit, closure measurement, `/check-npm` row, or workflow file + step only for **pnpm install policy**).
- **Decision**: one of **Dependency triage** labels.
- **Proposed change**: exact manifest/lockfile command or edit. If not applied yet, state that explicitly.
- **Rationale**: footprint (exclusive/total closure), supply-chain, maintenance, or verification risk.
- **User review required**: tests/build/typecheck to run; peer/plugin/CLI consumers; published-package or dynamic-import risk; approval before **Replace-with-Better** or any new direct dependency.

Use one block per package (or per protocol/CI finding), not a single-line summary, when the finding is non-trivial.
