# k6 skill: `k6 x docs` Setup Guide

Read this file when `k6 x docs` is not working — it covers how to provision (or build) the docs binary, and how to message the user if neither path succeeds.

## k6 v1.7.0+ (recommended) — no build required

As of k6 v1.7.0, the docs subcommand is **auto-provisioned** on first use (~30s, then cached).

```bash
k6 version   # confirm v1.7.0+

# Try without a version flag first (uses the bundle matching your k6 version):
k6 x docs 2>&1 | head -3

# If you get a 404 error, fall back to the previous version:
k6 x docs --version v1.6.1 2>&1 | head -3
```

Use the first command that returns a topic list as `DOCS_CMD`.

---

## Older k6 — manual build

If you're on k6 < v1.7.0, build the binary manually:

```bash
# Requires Go 1.21+ and xk6
go install go.k6.io/xk6/cmd/xk6@latest
xk6 build --with github.com/grafana/xk6-subcommand-docs@latest -o ./k6-with-docs
./k6-with-docs x docs 2>&1 | head -3
```

If this succeeds, set `DOCS_CMD = ./k6-with-docs x docs` and continue.

---

## Note for this session

Tell the user:

> `k6 x docs` is not working in this environment.
>
> **If you have k6 v1.7.0+:** run `k6 x docs` — it auto-provisions the docs binary.
> If that returns a 404 error, try `k6 x docs --version v1.6.1` as a fallback.
>
> **If you have an older k6:** I can build `./k6-with-docs` if `xk6` and Go 1.21+ are available.
> Would you like me to try?
>
> If nothing works, I'll fall back to web docs from grafana.com.
