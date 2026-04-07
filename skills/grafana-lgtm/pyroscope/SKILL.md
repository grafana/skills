---
name: pyroscope
license: Apache-2.0
description: >
  Grafana Pyroscope continuous profiling overview including profile types (CPU, memory, goroutine, mutex),
  flame graphs, diff views, Profiles Drilldown, and language support. Use when working with Pyroscope,
  analyzing flame graphs, optimizing code performance, or discussing continuous profiling architecture.
---

# Continuous Profiling with Grafana Pyroscope

## Value Proposition

Open-source continuous profiling platform that helps understand code performance at the line level in production.
Continuously collects profiling data with minimal overhead (< 2% CPU), enabling always-on performance analysis
across your entire application fleet.

**Key Differentiators**: Continuous (always-on) profiling, multi-language support, < 2% CPU overhead, flame graph
visualization, diff views for before/after comparison, integration with traces/metrics/logs.

## Profile Types

| Type | What It Shows | Use Case |
|------|-------------|----------|
| **CPU** | Functions consuming most CPU time | Find hot code paths, inefficient algorithms |
| **Memory** | Memory allocations and usage | Find memory leaks, excessive allocations |
| **Goroutine** (Go) | Goroutine creation and lifecycle | Detect goroutine leaks, deadlocks |
| **Mutex** | Lock contention and wait times | Optimize concurrent code |
| **Block** | Time blocking on sync primitives | Identify channel/I/O bottlenecks |
| **Off-CPU** | Where threads sleep or wait | Find I/O bottlenecks, waiting states |

**Supported languages**: Go, Java, Python, Ruby, Node.js, .NET, Rust, PHP.

## Flame Graphs

Interactive visualization of call stacks:
- **Width**: Proportional to time spent in each function
- **Height**: Call stack depth
- **Color**: Differentiate packages/modules
- Searchable, zoomable, with exact percentages in tooltips

### Diff View

Compare two profiles side-by-side to:
- Highlight functions that changed
- Identify performance regressions
- Validate optimization impact
- Compare before/after deployment

## Profiles Drilldown

Queryless profiling exploration (preinstalled in all Grafana instances):
- All services overview with CPU utilization
- Time-series visualization of performance trends
- Profile type selection (CPU, memory, goroutines)
- Source code integration (GitHub)

## Integration with Traces

Connect profiling data with distributed traces:

```yaml
jsonData:
  tracesToProfiles:
    datasourceUid: "pyroscope-uid"
    tags:
      - key: "service.name"
        value: "service_name"
    profileTypeId: "process_cpu:cpu:nanoseconds:cpu:nanoseconds"
```

**Profile type IDs**:
- CPU: `process_cpu:cpu:nanoseconds:cpu:nanoseconds`
- Memory: `memory:alloc_objects:count:space:bytes`
- Goroutines: `goroutines:goroutine:count::count`

Applications must emit span profile data with `pyroscope.profile.id` tag.

## Use Cases

- **Performance optimization**: Identify expensive code paths in production
- **Cost reduction**: Find resource-intensive functions to optimize infrastructure spend
- **Regression detection**: Compare profiles before/after deployments
- **Memory leak investigation**: Track allocation patterns over time
- **Concurrency debugging**: Identify lock contention and goroutine leaks

## Resources

- [Pyroscope Documentation](https://grafana.com/docs/pyroscope/latest/)
- [Profiles Drilldown App](https://github.com/grafana/profiles-drilldown)
- [Grafana Alloy Profiling](https://grafana.com/docs/alloy/)
