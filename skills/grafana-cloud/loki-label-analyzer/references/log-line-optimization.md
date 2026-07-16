# Log Line Optimization

These reduce storage costs (Scenario C in [cost-impact.md](cost-impact.md)). Establish a cost-per-GB baseline before implementing.

## Remove Timestamps from Log Lines

Each log entry already has a metadata timestamp — the inline timestamp is redundant (~30–34 bytes each, ~6% of a typical log line).

```alloy
loki.process "drop_timestamp" {
 forward_to = [...]
 // logfmt timestamps
 stage.replace {
 expression = "(?i)((?:time_?(?:stamp)?|ts|logdate|start_?time)=[^ \\n]+(?: |$))"
 replace = " "
 }
 // JSON timestamps
 stage.replace {
 expression = "(\"@?(?:time_?(?:stamp)?|ts|logdate|start_?time)\"\\s*:\\s*\"[^\"]+\",?)"
 replace = " "
 }
 // ISO-8601 at start of line
 stage.replace {
 expression = "^(\\d{4}-\\d{2}-\\d{2})T\\d{2}:\\d{2}(?::\\d{2}(?:\\.\\d{1,9})?Z?)?"
 replace = ""
 }
}
```

The original timestamp is still accessible at query time: `| line_format '{{ __timestamp__ | date "2006-01-02T15:04:05Z" }}'`

## Remove ANSI Color Codes

```alloy
loki.process "decolorize" {
 forward_to = [...]
 stage.decolorize {}
}
```

## Remove Duplicate Level Field (when `level` is already a label)

```alloy
stage.replace { expression = "(level=[^ ]+ )"; replace = "" }
```

## JSON Optimizations

```alloy
// Remove null values
stage.replace {
 expression = "(\\s*(\"[^\"]+\"\\s*:\\s*null)(?:\\s*,)?\\s*)"
 replace = ""
}

// Remove placeholder values ("-", "undefined", "null" strings)
stage.replace {
 expression = "(\\s*(\"[^\"]+\"\\s*:\\s*\"(?:-|null|undefined)\")(?:\\s*,)?\\s*)"
 replace = ""
}

// Remove empty values ("", [], {})
stage.replace {
 expression = "(\\s*,\\s*(\"[^\"]+\"\\s*:\\s*(\\[\\s*\\]|\\{\\s*\\}|\"\\s*\"))|(\"[^\"]+\"\\s*:\\s*(\\[\\s*\\]|\\{\\s*\\}|\"\\s*\"))\\s*,\\s*)"
 replace = ""
}
```

**Practical savings** (Istio access log example):
Starting at 753 bytes (minified) → after removing nulls, placeholders, unused fields, normalizing keys: **464 bytes — 38% reduction**.
