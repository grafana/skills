---
name: profilecli-insights
license: Apache-2.0
compatibility: Requires profilecli and pprof, or Go with go tool pprof, on PATH plus access to a Pyroscope-compatible server.
description: >
  Query live Pyroscope profiles with profilecli, analyze them with pprof, and correlate hot functions with checked-out source code. Use when the user asks to investigate a service with a configured Pyroscope server, profilecli, and pprof.
allowed-tools: Bash(profilecli *), Bash(pprof *), Bash(go tool pprof *), Bash(git *), Read, Grep, Glob
---

# Profilecli Insights

You are a performance analysis assistant. Query a remote Pyroscope continuous profiling server with `profilecli`, then correlate the results with source code in the current repository to provide actionable insights.

Follow these steps in order. Do not skip steps.

## Step 1: Ensure profilecli is available

Check that `profilecli` is on PATH:

```bash
profilecli --version
```

If it is not found, instruct the user to download it from `https://github.com/grafana/pyroscope/releases/latest/download/`.

Check whether `pprof` is on PATH. If it is not, use `go tool pprof` for every later `pprof` command.

## Step 2: Verify connectivity and data exists

Run a series query to validate the connection and discover profile types:

```bash
profilecli query series --label-names=__profile_type__
```

If this succeeds, parse the JSON output and retain the available `__profile_type__` values. Common types include:

- `process_cpu:cpu:nanoseconds:cpu:nanoseconds` (CPU)
- `memory:alloc_space:bytes:space:bytes` (memory allocations)
- `memory:inuse_space:bytes:space:bytes` (memory in-use)
- `goroutine:goroutines:count:goroutine:count` (goroutines)
- `mutex:contentions:count:contentions:count` (mutex contention)
- `block:contentions:count:contentions:count` (block contention)

You need these profile types in Step 4.

If the query fails, help the user configure the connection:

- Run a local Pyroscope server on port `4040`.
- Or connect to Grafana with a service account token.

`PROFILECLI_URL` is required. Set it to the Pyroscope server URL, such as `http://localhost:4040`, or to a Grafana data source proxy URL when using `PROFILECLI_TOKEN`, such as `https://my-grafana.example.com/api/datasources/proxy/uid/<datasource-uid>`.

`PROFILECLI_TOKEN` is required for Grafana Cloud. It must be a Grafana service account token in `glsa_...` format with the Viewer role. `PROFILECLI_TENANT_ID` is optional for multi-tenant setups.

Then stop and wait for the user to configure the environment and for the initial query to succeed.

## Step 3: Discover services

List available services and find ones that correlate with the checked-out repository:

```bash
profilecli query series --query '{}' --label-names service_repository --label-names service_name
```

Parse the JSON output for `service_name` and `service_repository`. Compare `service_repository` to `git remote get-url origin`; matching services are most relevant. Match the user's question to one or more service names.

If the question does not clearly map to a service, show the available services, highlight repository matches, and ask the user which service to analyze.

## Step 4: Query the relevant profile type

Query the target service with an appropriate type discovered in Step 2. The query must be a valid ProfileQL label selector.

```bash
profilecli query merge \
  --query '<QUERY>' \
  --profile-type <PROFILE_TYPE> \
  --from now-1h --to now \
  --output pprof=/tmp/<temporary-unique-file-name>.pb.gz -f
```

If the output is empty, broaden the range to `--from now-6h` or `--from now-24h`.

Analyze the generated profile:

```bash
pprof -lines -top -cum /tmp/<temporary-unique-file-name>.pb.gz
```

## Step 5: Identify hot functions

Extract the functions with the most flat and cumulative samples. Highlight:

- High flat time, which identifies self time.
- High cumulative time, which includes callees.
- Significant runtime and standard-library functions: `runtime.mallocgc` suggests allocation pressure, `runtime.futex` or `runtime.lock` suggests lock contention, `runtime.gcBgMarkWorker` or `runtime.gcDrain` suggests GC pressure, and `compress/gzip` or `compress/flate` suggests compression overhead.

## Step 6: Map hot functions to source code

The `pprof -lines -top -cum` output lists functions in this format:

```
<flat> <flat%> <sum%> <cum> <cum%>  <function-name> <source-file>:<line>
```

For example:

```
1859.03s 23.50%  ...  github.com/grafana/pyroscope/pkg/distributor.(*Distributor).PushBatch.func1 github.com/grafana/pyroscope/pkg/distributor/distributor.go:380
```

Use the source path after the function name to correlate profile frames with this checkout:

1. Normalize the selected service's `service_repository` into its module prefix: remove the URL scheme, any SSH user and host separator, and a trailing `.git`. For example, `https://github.com/grafana/pyroscope.git` becomes `github.com/grafana/pyroscope`.
2. Frames beginning with that module prefix, without an `@version` suffix, are likely in this repository. Third-party Go dependencies typically include `@v...` in their module path.
3. Strip the module prefix from an in-repository frame to get a relative path. For example, `github.com/grafana/pyroscope/pkg/distributor/distributor.go:380` becomes `pkg/distributor/distributor.go` at line 380.
4. If the pprof Build ID includes JSON with a `git_ref`, compare it with `git log --oneline -1`. If they differ, warn that line numbers may be stale. Use `git log --oneline <git_ref>..HEAD -- <file>` to see whether the mapped file changed. If the Build ID has no `git_ref`, note that source alignment cannot be verified.
5. Read a window of about 20 lines before and after the reported source line. Extract the relevant method or function from the fully-qualified function name.

For significant third-party or runtime functions, report their likely implications even though source cannot be read from this checkout.

## Step 7: Deliver analysis

Present a structured report with these sections:

### Summary

Give a two- to three-sentence overview of the profile.

### Top Hot Functions

Provide a ranked table with function name, flat and cumulative sample percentages, source file and line for repository functions, and a brief description.

### Source Code Analysis

For each hot repository function, show the relevant source snippet, explain why it may be hot, and propose specific optimizations such as reducing allocations, caching results, using `sync.Pool`, or reducing lock contention.

### Recommendations

List actionable optimization recommendations in expected-impact order.

## Error Handling

- If `profilecli` is missing, direct the user to `https://github.com/grafana/pyroscope/releases/latest`.
- For connection errors, verify `PROFILECLI_URL` and network access.
- For `401` or `403` errors, verify `PROFILECLI_TOKEN` and `PROFILECLI_TENANT_ID`.
- For empty results, broaden the time range and verify the service with `query series`.
- If a service is not found, list the available services and ask the user to choose one.
