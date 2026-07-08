# Fix snippets (one per FAIL)

## Tool version

```bash
npm install -g npm@11.15.0
```

```bash
yarn set version 4.14.0
```

```bash
npm install -g pnpm@11.0.0
```

## Lifecycle scripts

`.npmrc`:

```
ignore-scripts=true
```

`pnpm-workspace.yaml` (pnpm 11 — do not use `.npmrc` for this):

```yaml
strictDepBuilds: true
dangerouslyAllowAllBuilds: false
allowBuilds: []
```

```bash
yarn config set enableScripts false
```

## Unsafe dependency protocols

`.npmrc`:

```
allow-git=none
```

`.yarnrc.yml` (block all git deps):

```yaml
approvedGitRepositories: []
```

`.yarnrc.yml` (Grafana internal repos):

```yaml
approvedGitRepositories:
  - "https://github.com/grafana/*"
  - "ssh://git@github.com/grafana/*"
  - "git@github.com:grafana/*"
```

`pnpm-workspace.yaml`:

```yaml
blockExoticSubdeps: true
```

## Minimum release age

`.npmrc` (days):

```
min-release-age=3
```

`.yarnrc.yml`:

```yaml
npmMinimalAgeGate: 4320  # or "3d"
```

`pnpm-workspace.yaml` (minutes):

```yaml
minimumReleaseAge: 4320
```

`.npmrc` (pnpm 10, minutes):

```
minimum-release-age=4320
```
