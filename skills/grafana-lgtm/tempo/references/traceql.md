# TraceQL — query language

Structure: `{ filters } | pipeline`

## Attribute scopes

```traceql
span.http.status_code        # span-level
resource.service.name        # resource-level (from SDK)
event.name                   # event-level
name                         # intrinsic: span operation name
status                       # intrinsic: ok | error | unset
duration                     # intrinsic: span duration
kind                         # intrinsic: server | client | producer | consumer | internal
traceDuration                # intrinsic: entire trace duration
rootServiceName              # intrinsic: service of the root span
rootName                     # intrinsic: operation name of the root span
```

## Operators

```
=   !=   >   <   >=   <=      # comparison
=~  !~                         # regex (Go RE2)
&&  ||  !                      # logical
```

## Essential queries

```traceql
# All errors
{ status = error }

# Slow requests from a service
{ resource.service.name = "frontend" && duration > 1s }

# HTTP 5xx
{ span.http.status_code >= 500 }

# Count errors per trace (>=2)
{ status = error } | count() >= 2

# Select fields
{ status = error } | select(span.http.url, duration, resource.service.name)

# Structural: server span with downstream error
{ kind = server } >> { status = error }

# Both conditions present anywhere
{ span.db.system = "redis" } && { span.db.system = "postgresql" }

# Deterministic most-recent
{ resource.service.name = "api" } with (most_recent=true)
```

## TraceQL metrics

```traceql
# Error rate per service
{ status = error } | rate() by (resource.service.name)

# P99 latency
{ kind = server } | quantile_over_time(duration, .99) by (resource.service.name)
```

## Best-practice notes

- Always include time bounds (`start` / `end`) on search to limit scope
- Use structural operators (`>>`, `&&`) for root-cause patterns
- `attribute != nil` for existence checks
- `with (most_recent=true)` for deterministic recent results
- Scope tag discovery with a TraceQL query to cut noise
