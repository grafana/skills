# Dependency protocol allow-list

## Safe protocols

- Valid **semver range** (`^1.2.3`, `~1.0`, `1.x`, `*`, exact `1.2.3`)
- `workspace:` (`workspace:^`, `workspace:*`)
- `patch:` (`patch:left-pad@1.0.0#~/patches/left-pad.patch`)
- `npm:` alias resolving to semver (`npm:lodash@^4`)

Everything else is unsafe — including yarn bare GitHub shorthand `user/repo` or `user/repo#commit`.

## Workspace scan

Scan root `package.json` and every workspace member. Discover members from `pnpm-workspace.yaml`, npm/yarn `workspaces`, `lerna.json`, or `rush.json`.

Sections: `dependencies`, `devDependencies`, `optionalDependencies`, `peerDependencies`.

Flag format:

```
path/to/package.json → name → value (protocol)
```

## Detection order

1. Explicit `<scheme>:` prefix (`git:`, `git+https:`, `github:`, `link:`, `file:`, `exec:`, `jsr:`, …)
2. `git@…` SSH URLs
3. `http://` / `https://` tarball URLs
4. Bare `user/repo` or `user/repo#…` (yarn GitHub shorthand)
5. Not matching 1–4 and not valid semver → `(unknown)`

Full yarn protocol list: <https://yarnpkg.com/protocols>
