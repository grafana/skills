# Per-manager pass/fail criteria

## Tool version thresholds

| Manager | Command | Minimum | Notes |
|---------|---------|---------|-------|
| npm | `npm --version` | 11.15.0 | `allow-git` in 11.15; `min-release-age` in 11.10 |
| yarn | `yarn --version` | 4.14.0 | `approvedGitRepositories` in 4.14 |
| pnpm | `pnpm --version` | 11.0.0 | pnpm 11 defaults `minimumReleaseAge`, `strictDepBuilds`, `blockExoticSubdeps` on |

If `packageManager` is pinned in root `package.json`, verify the pin meets the threshold. Use semver comparison.

## Lifecycle scripts

| Manager | Read | PASS | FAIL |
|---------|------|------|------|
| yarn | `.yarnrc.yml` | `enableScripts: false`, or key absent (yarn 4 default `false`) | `enableScripts: true` |
| npm | `.npmrc` | `ignore-scripts=true` | missing or `ignore-scripts=false` |
| pnpm ≥ 11 | `pnpm-workspace.yaml` | `strictDepBuilds` unset/`true` AND `dangerouslyAllowAllBuilds` unset/`false` AND `allowBuilds` unset/`[]` | `strictDepBuilds: false` or `dangerouslyAllowAllBuilds: true` or `allowBuilds` non-empty |
| pnpm 10.x | `.npmrc`, `pnpm-workspace.yaml`, `package.json#pnpm` | `.npmrc` has `ignore-scripts=true` OR `strictDepBuilds: true` | neither, or `ignore-scripts=false`, or `strictDepBuilds: false` |
| pnpm < 10 | `.npmrc` | `ignore-scripts=true` | otherwise |

pnpm 11+ ignores build-script settings in `package.json#pnpm` and non-auth `.npmrc` entries.

Detail column: if `allowBuilds` (pnpm 11) or `onlyBuiltDependencies` (pnpm 10) lists packages, list them (these are explicit build-script exemptions and should be treated as a FAIL per the criteria above).

## Unsafe dependency protocols

| Manager | Read | PASS | FAIL |
|---------|------|------|------|
| npm | `.npmrc` | `allow-git=none` or `allow-git=root` | missing, `allow-git=all` |
| yarn | `.yarnrc.yml` + `package.json` scan | Posture A: `approvedGitRepositories: []` or all entries scoped to `grafana` org (three URL forms). Posture B: key omitted with explicit "do not add" comment AND scan clean | Offending `approvedGitRepositories` entries, or missing key + no policy comment + scan finds unsafe deps |
| pnpm ≥ 11 | `pnpm-workspace.yaml` | `blockExoticSubdeps` unset/`true` | `blockExoticSubdeps: false` |
| pnpm 10.x | `pnpm-workspace.yaml`, `package.json#pnpm` | `blockExoticSubdeps: true` | unset (default `false`) or `false` |

npm < 11.15.0: `allow-git` in `.npmrc` is not enforced — call out in detail.

Grafana yarn allow-list URL forms (same repos, different patterns):

- `https://github.com/grafana/*`
- `ssh://git@github.com/grafana/*`
- `git@github.com:grafana/*`

## Minimum release age

3 days = **4320 minutes**. npm uses **days** (integer); yarn and pnpm use **minutes** (integer).

| Manager | Read | PASS | FAIL |
|---------|------|------|------|
| npm | `.npmrc` | `min-release-age` ≥ `3` | missing (default off) |
| yarn | `.yarnrc.yml` | `npmMinimalAgeGate` ≥ 4320 min (accepts `4320`, `"3d"`, `"72h"`) | missing or below threshold (default `0`) |
| pnpm ≥ 11 | `pnpm-workspace.yaml` | `minimumReleaseAge` ≥ `4320` | unset (default `1440`) or below; also flag `minimumReleaseAgeStrict: false` |
| pnpm 10.x | `.npmrc`, `pnpm-workspace.yaml`, `package.json#pnpm` | `minimum-release-age` / `minimumReleaseAge` ≥ `4320` | otherwise (default `0`) |
| pnpm < 10 | — | — | setting unavailable; recommend upgrade |

Detail column: list `npmPreapprovedPackages` (yarn) or `allowBuilds` exemptions when set.
