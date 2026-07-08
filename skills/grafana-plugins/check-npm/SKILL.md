---
name: check-npm
license: Apache-2.0
description: >-
  Audit a JavaScript/TypeScript repo's npm, yarn, or pnpm package manager
  configuration for supply-chain hardening. Use when the user invokes /check-npm
  or asks to audit package manager security, lifecycle scripts, git dependencies,
  ignore-scripts, min-release-age, or similar hardening checks in a Grafana plugin
  or JS/TS project.
---

# npm / yarn / pnpm Supply-Chain Hardening Audit

Read-only audit of the current workspace root against four hardening criteria. Do NOT modify any files.

## Step 0 — Detect package manager

If there is no `package.json` at the workspace root, stop and tell the user this skill only applies to JS/TS repos.

Otherwise, determine the package manager in priority order:

1. `packageManager` field in `package.json` (e.g. `"yarn@4.14.0"` → yarn)
2. Lockfile presence: `yarn.lock` → yarn, `package-lock.json` → npm, `pnpm-lock.yaml` → pnpm
3. Default to npm

State which one the repo uses. The remaining checks key off this.

## Step 1 — Tool version

Run the version command for the detected manager:

- **npm**: `npm --version` → required ≥ **11.15.0** (`--allow-git` shipped in 11.15.0; `min-release-age` shipped in 11.10.0)
- **yarn**: `yarn --version` → required ≥ **4.14.0** (`approvedGitRepositories` shipped in 4.14.0)
- **pnpm**: `pnpm --version` → required ≥ **11.0.0** (pnpm 11 turns `minimumReleaseAge`, `strictDepBuilds`, and `blockExoticSubdeps` on by default)

If `packageManager` is pinned in `package.json`, verify the pinned version meets the threshold.

Use semver comparison, not string compare.

## Step 2 — Lifecycle scripts disabled

Where each manager looks for the setting depends on its major version:

- **yarn**: read `.yarnrc.yml` at workspace root.
  - PASS if `enableScripts: false` is set explicitly, OR if `.yarnrc.yml` is absent / does not mention `enableScripts` (yarn 4 defaults to `false`).
  - FAIL only if `enableScripts: true` is set.
- **npm**: read `.npmrc` at workspace root.
  - PASS if it contains `ignore-scripts=true`.
  - FAIL otherwise (npm defaults to RUN scripts).
- **pnpm ≥ 11**: read `pnpm-workspace.yaml` at the workspace root. On pnpm 11+, pnpm no longer reads build-script settings from `package.json#pnpm` or non-auth `.npmrc` entries — those are silently ignored.
  - PASS if `strictDepBuilds` is unset or `true` (default `true` since pnpm 11), AND `dangerouslyAllowAllBuilds` is unset or `false` (default `false`).
  - FAIL if `strictDepBuilds: false` or `dangerouslyAllowAllBuilds: true`.
  - If `allowBuilds` is set, list every key whose value is `true` in the detail column — those packages can still execute scripts.
- **pnpm 10.x** (legacy): read `.npmrc`, `pnpm-workspace.yaml`, and the `pnpm` field in root `package.json` (pnpm 10 still reads `package.json#pnpm`).
  - PASS if `.npmrc` contains `ignore-scripts=true`, OR `pnpm-workspace.yaml` has `strictDepBuilds: true` (default since pnpm 10.3).
  - FAIL if neither holds, or if `ignore-scripts=false` is set, or `strictDepBuilds: false`.
  - If `onlyBuiltDependencies` is set, list those packages — they're the build-script allow-list on pnpm 10.
- **pnpm < 10**: read `.npmrc`.
  - PASS only if `ignore-scripts=true`.
  - FAIL otherwise.

## Step 3 — Unsafe dependency protocols

Yarn (and to a lesser extent npm) supports many ways to declare a dependency beyond a plain semver range. Several of them resolve to arbitrary remote sources (git, tarball URLs, exec scripts, …) that bypass the registry and the min-release-age gate.

### Allow-list

The only dependency protocols considered safe are:

- a valid **semver range** (e.g. `^1.2.3`, `~1.0`, `1.x`, `*`, exact pin `1.2.3`)
- `workspace:` (e.g. `workspace:^`, `workspace:*`)
- `patch:` (e.g. `patch:left-pad@1.0.0#~/patches/left-pad.patch`)
- `npm:` aliases that themselves resolve to a semver range (e.g. `npm:lodash@^4`)

Anything else — including yarn's bare GitHub shorthand `user/repo` or `user/repo#commit-ish` (which silently resolves to a git dep, even with no `git`/`github:` prefix) — is flagged. See <https://yarnpkg.com/protocols> for the full list of yarn protocols.

### Per-manager registry config

- **npm**: read `.npmrc`.
  - PASS if `allow-git=none` (or `allow-git=root`) is set.
  - FAIL if missing (default is `all`, which allows arbitrary git deps) or if `allow-git=all`.
  - Note: `--allow-git` was added in npm 11.15.0. If detected npm is < 11.15.0, the `.npmrc` setting is not enforced — call this out.
- **yarn**: read `.yarnrc.yml`. There are two valid hardened postures — pick the one the repo's `.yarnrc.yml` documents (look for a comment near the key) and audit against that:
  - **Posture A — empty allow-list:** PASS if `approvedGitRepositories: []` (blocks all git deps at the resolver). PASS if every entry is scoped to the `grafana` GitHub org (Grafana convention; entries should be listed once per normalized URL form — `https://github.com/grafana/*` and `ssh://git@github.com/grafana/*` and `git@github.com:grafana/*` are three different patterns even though they reference the same repos). FAIL if any entry is scoped outside the `grafana` org — list the offending patterns.
  - **Posture B — deliberately omitted:** some teams (e.g. grafana/grafana itself) treat the key as a footgun because a future contributor can broaden it. In that case the `.yarnrc.yml` should carry an explicit "do not add `approvedGitRepositories`" comment, and the repo relies on the `package.json` scan below as the sole git-dep gate.
  - **FAIL only if** `approvedGitRepositories:` is missing *and* the file has no policy comment forbidding it *and* the `package.json` scan in the next section finds any unsafe entry — in that case yarn would actually install the offending dep because it falls back to pre-4.14 behavior. If the scan is clean, PASS with detail `no allow-list; scan clean`.
- **pnpm ≥ 11**: read `pnpm-workspace.yaml`.
  - PASS if `blockExoticSubdeps` is unset or `true` (default `true` since pnpm 11).
  - FAIL if `blockExoticSubdeps: false`.
- **pnpm 10.x**: read `pnpm-workspace.yaml` and root `package.json#pnpm`.
  - PASS if `blockExoticSubdeps: true`.
  - FAIL if unset (default `false` on pnpm 10) or `blockExoticSubdeps: false`.

### Scan workspace `package.json` files

For **all package managers**, scan the root `package.json` **and every workspace member** `package.json` (discover members from `pnpm-workspace.yaml`, npm/yarn `workspaces`, or `lerna.json` / `rush.json` when present). For each file, scan `dependencies` / `devDependencies` / `optionalDependencies` / `peerDependencies`. List every entry whose value is **not** on the allow-list, formatted as:

    path/to/package.json → name → value (protocol)

Detect protocols by matching, in order:

1. Explicit `<scheme>:` prefix (`git:`, `git+https:`, `git+ssh:`, `github:`, `gitlab:`, `bitbucket:`, `link:`, `portal:`, `file:`, `exec:`, `jsr:`, …)
2. `git@…` SSH-style URLs
3. Plain URLs starting with `http://`, `https://` (tarball)
4. Bare `user/repo` or `user/repo#…` (yarn GitHub shorthand, resolves to git)
5. If none of the above match and the string is not a valid semver range, flag as `(unknown)`.

Any entry that matches 1–5 would be blocked under `allow-git=none` (npm) or rejected if not in `approvedGitRepositories` (yarn).

## Step 4 — Minimum release age ≥ 3 days

Units differ per manager — **npm uses days (integer), yarn and pnpm use minutes (integer)**. 3 days = 4320 minutes.

- **npm**: read `.npmrc`.
  - PASS if `min-release-age` is set to an integer ≥ `3`.
  - **FAIL** if missing. `min-release-age` was added in npm 11.10.0 but ships **OFF** by default (`null`) — an unset value means no release-age gate, not a default 3-day window.
  - If detected npm is < 11.10.0, also recommend upgrading.
- **yarn**: read `.yarnrc.yml`. The only key is `npmMinimalAgeGate:` (added in yarn 4.10 — confirmed via `yarn config get npmMinimalAgeGate`; the key `npmMinimumReleaseAge` does not exist in yarn 4.x).
  - PASS if `npmMinimalAgeGate:` is set to a value equivalent to ≥ 3 days. Both numeric minutes (`4320`) and duration strings (`"3d"`, `"72h"`) are accepted by yarn — convert before comparing.
  - FAIL if the key is missing, or if the resolved value is below the threshold. Default on yarn 4.x is `0` (gate inactive — `yarn config get` returns `0` when the key is unset), so a missing line is genuinely unprotected, not a hidden default.
  - If `npmPreapprovedPackages:` is set, list the exempted patterns in the detail column — those packages bypass the age gate (a controlled exception, typically used for first-party `@org/*` packages).
- **pnpm ≥ 11**: read `pnpm-workspace.yaml` at the workspace root. `.npmrc` entries for this setting are ignored on pnpm 11; `package.json#pnpm` is not read on pnpm 11+.
  - PASS if `minimumReleaseAge:` is set to an integer ≥ `4320`.
  - **FAIL** if `minimumReleaseAge` is unset or below `4320`. pnpm 11 defaults to `1440` (1 day) when unset — below the 3-day bar. Recommend setting `minimumReleaseAge: 4320` explicitly.
  - Also flag `minimumReleaseAgeStrict: false` if set — without strict mode pnpm falls back to immature versions when no mature one satisfies the range.
- **pnpm 10.x**: read `.npmrc`, `pnpm-workspace.yaml`, and root `package.json#pnpm`.
  - PASS if either contains `minimum-release-age` / `minimumReleaseAge` ≥ `4320`.
  - FAIL otherwise (pnpm 10 default is `0`).
- **pnpm < 10**: setting not available. FAIL with a recommendation to upgrade.

## Step 5 — Report

Print a single markdown table:

| # | Check | Status | Detail |
|---|---|---|---|
| 0 | Package manager | (npm / yarn / pnpm) | version: x.y.z (pinned: y.y.y) |
| 1 | Tool version ≥ threshold | PASS / FAIL | `actual` vs `required` |
| 2 | Scripts disabled | PASS / FAIL | config line found, "missing", or `default applies (pnpm 11)` |
| 3 | Unsafe dep protocols | PASS / FAIL | registry config state (allow-list / "deliberately omitted" / "missing"), and list of flagged `package.json` entries |
| 4 | Min release age ≥ 3 days | PASS / FAIL | config line + value; for pnpm 11 unset default (`1440 min`) report FAIL |

Use `PASS` / `FAIL` only — no emojis. Row 0 reports the package manager name and version, not a status.

Below the table, for every FAIL, give exactly one fix snippet the user can paste.

**npm tool version** → upgrade npm (example):

    npm install -g npm@11.15.0

**yarn tool version** → set Yarn to a supported version (do NOT route through Corepack):

    yarn set version stable

**pnpm tool version** → upgrade pnpm (example):

    npm install -g pnpm@11

**npm scripts disabled** → add to `.npmrc`:

    ignore-scripts=true

**pnpm scripts disabled (v11)** → add to `pnpm-workspace.yaml` (do not put this in `.npmrc` on v11 — it's ignored):

    strictDepBuilds: true
    dangerouslyAllowAllBuilds: false

**pnpm scripts disabled (v10)** → add to `.npmrc`:

    ignore-scripts=true

**yarn scripts disabled** (only if explicitly `true`) → run:

    yarn config set enableScripts false

**npm unsafe dep protocols** → add to `.npmrc` and remove the offending entries from `package.json`:

    allow-git=none

**yarn unsafe dep protocols** → either rewrite the offending entries to semver/`workspace:`/`patch:`, or explicitly allow internal repos by adding to `.yarnrc.yml`. Use an empty list (`approvedGitRepositories: []`) to block all git deps outright:

    approvedGitRepositories:
      - "https://github.com/grafana/*"
      - "ssh://git@github.com/grafana/*"
      - "git@github.com:grafana/*"

**npm min release age** → add to `.npmrc` (value is **days as an integer**):

    min-release-age=3

**pnpm min release age (v11, unset or < 4320)** → add to `pnpm-workspace.yaml` (value is **minutes**):

    minimumReleaseAge: 4320

**pnpm exotic deps (v11)** → ensure `pnpm-workspace.yaml` does not disable blocking:

    blockExoticSubdeps: true

**pnpm min release age (v10)** → add to `.npmrc` (value is **minutes**):

    minimum-release-age=4320

**yarn min release age** → in `.yarnrc.yml`. The only valid key is `npmMinimalAgeGate` (yarn ≥ 4.10). On yarn < 4.10 there is no release-age gate at all — upgrade yarn first via `yarn set version stable`. Accepts numeric minutes or duration strings:

    npmMinimalAgeGate: 4320  # or "3d"

If everything PASSes, finish with "All checks passed." and stop.

## Constraints

- Read manager config at the workspace root (`.npmrc`, `.yarnrc.yml`, `pnpm-workspace.yaml`). For the dependency-protocol scan, also read every workspace member `package.json` (see Step 3).
- Do NOT modify any files. This is a read-only audit.
- Be concise. The whole report should fit in one screen.
