---
name: check-npm
license: Apache-2.0
disable-model-invocation: false
description: >-
  Audit a JavaScript/TypeScript repo's npm, yarn, or pnpm configuration for
  supply-chain hardening: tool version, lifecycle scripts, unsafe dependency
  protocols, and minimum release age ≥3 days. Use when the user invokes
  /check-npm or asks to audit package manager security, lifecycle scripts, git
  dependencies, ignore-scripts, min-release-age, allow-git,
  approvedGitRepositories, strictDepBuilds, or blockExoticSubdeps in a Grafana
  plugin or JS/TS project.
---

# npm / yarn / pnpm supply-chain audit

Read-only audit of the workspace root. Do not modify any files.

## 0. Detect package manager

```bash
test -f package.json || { echo "STOP: no package.json at workspace root"; exit 1; }
jq -r '.packageManager // "unset"' package.json
ls -1 yarn.lock package-lock.json pnpm-lock.yaml 2>/dev/null || true
```

If no `package.json`, stop. Priority: `packageManager` → lockfile → default npm.

## 1. Tool version

```bash
npm --version    # required ≥ 11.15.0
yarn --version   # required ≥ 4.14.0
pnpm --version   # required ≥ 11.0.0
```

Use semver comparison. Verify pinned `packageManager` meets threshold.

| Manager | Minimum |
|---------|---------|
| npm | 11.15.0 |
| yarn | 4.14.0 |
| pnpm | 11.0.0 |

## 2. Lifecycle scripts disabled

```bash
grep -E '^ignore-scripts=' .npmrc 2>/dev/null
grep -E 'enableScripts:' .yarnrc.yml 2>/dev/null
grep -E 'strictDepBuilds:|dangerouslyAllowAllBuilds:|allowBuilds:' pnpm-workspace.yaml 2>/dev/null
```

| Manager | PASS | FAIL |
|---------|------|------|
| npm | `.npmrc` has `ignore-scripts=true` | missing or `false` |
| yarn | `enableScripts: false` or key absent | `enableScripts: true` |
| pnpm ≥ 11 | `strictDepBuilds` unset/`true`, `dangerouslyAllowAllBuilds` unset/`false`, and `allowBuilds` unset/`[]` | `strictDepBuilds: false`, `dangerouslyAllowAllBuilds: true`, or `allowBuilds` non-empty |
| pnpm 10 | `.npmrc` `ignore-scripts=true` OR `strictDepBuilds: true` | neither |

pnpm 11+ ignores script settings in `.npmrc` and `package.json#pnpm`. pnpm 10 / yarn edge cases: [references/managers.md](references/managers.md).

## 3. Unsafe dependency protocols

Registry:

```bash
grep -E '^allow-git=' .npmrc 2>/dev/null
grep -E 'approvedGitRepositories:' .yarnrc.yml 2>/dev/null
grep -E 'blockExoticSubdeps:' pnpm-workspace.yaml 2>/dev/null
```

Scan workspace `package.json` files (`dependencies`, `devDependencies`, `optionalDependencies`, `peerDependencies`). Prefer workspace-member discovery (pnpm-workspace.yaml / root workspaces / lerna / rush) per [references/protocols.md](references/protocols.md), then scan only those manifests. Fallback (may overmatch non-workspace manifests):

    find . -name package.json -not -path '*/node_modules/*'

**Safe values only:** semver range, `workspace:`, `patch:`, `npm:` alias to semver. Flag everything else (git URLs, tarballs, `user/repo` shorthand, `file:`, `link:`, `exec:`, …) as `path → name → value (protocol)`.

| Manager | PASS | FAIL |
|---------|------|------|
| npm | `allow-git=none` or `root` | missing or `all` |
| yarn | `approvedGitRepositories: []` or grafana-scoped list, or omitted with policy comment + clean scan | unsafe entries or broad allow-list |
| pnpm ≥ 11 | `blockExoticSubdeps` unset/`true` | `false` |
| pnpm 10.x | `blockExoticSubdeps: true` | unset (default `false`) or `false` |

Protocol detection order and yarn posture details: [references/protocols.md](references/protocols.md).

## 4. Minimum release age ≥ 3 days

3 days = 4320 minutes. npm uses **days**; yarn and pnpm use **minutes**.

```bash
grep -E '^min(imum)?-release-age=' .npmrc 2>/dev/null
grep -E 'npmMinimalAgeGate:' .yarnrc.yml 2>/dev/null
grep -E 'minimumReleaseAge:|minimumReleaseAgeStrict:' pnpm-workspace.yaml 2>/dev/null
```

| Manager | PASS | FAIL |
|---------|------|------|
| npm | `min-release-age` ≥ `3` | missing |
| yarn | `npmMinimalAgeGate` ≥ 4320 min | missing or below |
| pnpm ≥ 11 | `minimumReleaseAge` ≥ `4320` | unset (default `1440`) or below |
| pnpm 10 | `minimum-release-age` / `minimumReleaseAge` ≥ `4320` | missing |

Flag `minimumReleaseAgeStrict: false` on pnpm 11.

## 5. Report

| # | Check | Status | Detail |
|---|---|---|---|
| 0 | Package manager | (npm / yarn / pnpm) | version: x.y.z (pinned: y.y.y if set) |
| 1 | Tool version ≥ threshold | PASS / FAIL | `actual` vs `required` |
| 2 | Scripts disabled | PASS / FAIL | config line or "missing" |
| 3 | Unsafe dep protocols | PASS / FAIL | registry state + flagged entries |
| 4 | Min release age ≥ 3 days | PASS / FAIL | config + value |

Use `PASS` / `FAIL` only — no emojis.

For each FAIL, one paste-ready fix:

```ini
# npm — .npmrc
ignore-scripts=true
allow-git=none
min-release-age=3
```

```yaml
# pnpm 11 — pnpm-workspace.yaml
strictDepBuilds: true
dangerouslyAllowAllBuilds: false
allowBuilds: []
minimumReleaseAge: 4320
blockExoticSubdeps: true
```

```yaml
# yarn — .yarnrc.yml
npmMinimalAgeGate: 4320
```

More fixes (tool upgrades, yarn git allow-list, pnpm 10): [references/fix-snippets.md](references/fix-snippets.md).

If all PASS: "All checks passed." and stop.
