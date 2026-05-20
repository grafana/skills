# Alloy Configuration Language Syntax

> Reference for Alloy's configuration syntax (`.alloy` files). For the canonical docs, see
> https://grafana.com/docs/alloy/latest/get-started/configuration-syntax/.

## File format

- Extension: `.alloy`
- Encoding: UTF-8
- Whitespace-insensitive; one or more components per file
- Comments: `//` line comment, `/* ... */` block comment

A config file is a sequence of top-level **blocks** (components and configuration blocks) and
**attributes**.

## Blocks

Blocks declare either a configuration block (`logging`, `http`, `tracing`, `remotecfg`,
`clustering`, ...) or a **component** instance.

```alloy
BLOCK_TYPE "LABEL" {
  attribute = value

  nested_block {
    attribute = value
  }
}
```

- `BLOCK_TYPE` is dotted (e.g. `prometheus.scrape`, `otelcol.receiver.otlp`).
- `"LABEL"` is the user-chosen instance name. The `BLOCK_TYPE.LABEL` pair must be unique.
- Some top-level blocks have no label (`logging`, `http`, `tracing`, `remotecfg`, `clustering`).

```alloy
// Two instances of the same component type, distinguished by label
prometheus.scrape "api" {
  targets    = [{__address__ = "api.example.com:8080"}]
  forward_to = [prometheus.remote_write.cloud.receiver]
}

prometheus.scrape "db" {
  targets    = [{__address__ = "db.example.com:9090"}]
  forward_to = [prometheus.remote_write.cloud.receiver]
}
```

## Attributes

Attributes are `NAME = VALUE` pairs inside a block.

```alloy
scrape_interval = "30s"
enabled         = true
targets         = [{__address__ = "localhost:9090"}]
```

Attribute names are unquoted identifiers. Values can be literals, references, function calls, or
arbitrary expressions.

## Component model

Every component has two halves:

1. **Arguments** — the attributes and nested blocks you write.
2. **Exports** — values the component publishes for other components to consume.

Reference an export with `BLOCK_TYPE.LABEL.export_name`:

```alloy
local.file "api_key" {
  filename = "/etc/secrets/api.key"
}

prometheus.remote_write "cloud" {
  endpoint {
    url = "https://prometheus.example.com/api/v1/write"
    basic_auth {
      username = "metrics"
      password = local.file.api_key.content   // <- export reference
    }
  }
}
```

When a referenced export changes, Alloy re-evaluates and restarts dependent components
automatically — you do not manually wire updates.

## Data types

| Type       | Example                                                   |
|------------|-----------------------------------------------------------|
| `number`   | `42`, `3.14`, `-7`                                        |
| `string`   | `"hello"`, multi-line `"""\nfoo\nbar\n"""` (raw)          |
| `bool`     | `true`, `false`                                           |
| `null`     | `null`                                                    |
| `array`    | `[1, 2, 3]`, `[{__address__ = "host:9090"}]`              |
| `object`   | `{ key = "value", other = 1 }`                            |
| `function` | values returned by stdlib (`sys.env`, etc.)               |
| `capsule`  | opaque internal type (e.g. component receivers/handlers)  |

Object keys can be unquoted identifiers (`key = "v"`) or quoted strings (`"key" = "v"`). Quoted
keys are required when the key isn't a valid identifier — e.g. it contains a hyphen
(`"node-name" = "..."`) or starts with a digit. Identifiers built only from letters, digits, and
underscores (including leading underscores like `__address__`) are valid unquoted; quoting them is
purely a convention borrowed from Prometheus-style metadata labels.

## Expressions

Expressions appear on the right-hand side of any attribute. Supported forms:

```alloy
// Literals
x = 1
y = "string"
z = true

// Arithmetic, comparison, logical operators
a = 1 + 2 * 3            // 7
b = (1 + 2) * 3          // 9
c = 10 > 5 && !false     // true
d = "https://" + host    // string concatenation

// Component reference
e = prometheus.remote_write.cloud.receiver

// Function call
f = sys.env("HOME")
g = encoding.from_json(local.file.config.content)

// Indexing and field access
h = my_array[0]
i = my_object.field
j = my_object["field-with-dash"]
```

Operator precedence (highest to lowest, standard):

1. Unary `!`, `-`
2. `*`, `/`, `%`
3. `+`, `-`
4. `<`, `<=`, `>`, `>=`
5. `==`, `!=`
6. `&&`
7. `||`

Use parentheses to override precedence.

## References to other components

Format: `<block_type>.<label>.<export>`.

```alloy
// Targets export from discovery, consumed by scrape
prometheus.scrape "k8s" {
  targets    = discovery.kubernetes.pods.targets
  forward_to = [prometheus.remote_write.cloud.receiver]
}
```

Forwarding arrays are common: `forward_to = [<recipient>.input]` or `[<recipient>.receiver]`. The
exact export name (`input`, `receiver`, `handler`, ...) depends on the recipient component.

## Standard library

The stdlib mixes two shapes: most functions live under a **namespace** and are called as
`namespace.function(...)` (e.g. `sys.env`, `string.replace`); a handful are **top-level** functions
called by their bare name (e.g. `coalesce`, `json_path`). The most-used:

| Name                                              | Shape       | Useful members                                                            |
|---------------------------------------------------|-------------|---------------------------------------------------------------------------|
| `sys`                                             | namespace   | `sys.env("VAR")` — read environment variable                              |
| `constants`                                       | namespace   | `constants.hostname`, `constants.os`, `constants.arch`                    |
| `array`                                           | namespace   | `array.concat(a, b)`, `array.combine_maps(...)`                           |
| `convert`                                         | namespace   | `convert.nonsensitive(...)`, type casts                                   |
| `encoding`                                        | namespace   | `encoding.from_json(...)`, `encoding.from_yaml(...)`                      |
| `file`                                            | namespace   | `file.path_join(...)`                                                     |
| `string`                                          | namespace   | `string.to_upper`, `string.to_lower`, `string.replace`, `string.split`    |
| `coalesce(a, b, c)`                               | top-level   | First non-null/non-empty argument                                         |
| `json_path(doc, "$.field")`                       | top-level   | Extract values from a JSON document                                       |

Full reference: https://grafana.com/docs/alloy/latest/reference/stdlib/.

```alloy
// Typical patterns
password = sys.env("GRAFANA_API_KEY")
field    = "spec.nodeName=" + coalesce(sys.env("HOSTNAME"), constants.hostname)
url      = "https://" + sys.env("HOST") + "/api"
config   = encoding.from_json(local.file.json_config.content)
```

## Top-level configuration blocks

Unlike component blocks, these are unlabeled and appear at most once.

```alloy
logging {
  level  = "info"     // debug | info | warn | error
  format = "logfmt"   // logfmt | json
}

http {
  listen_addr = "0.0.0.0:12345"   // Alloy UI + /metrics endpoint
}

tracing {
  sampling_fraction = 0.1
  write_to          = [otelcol.exporter.otlp.default.input]
}

remotecfg {
  url = "https://fleet-management.grafana.net"
  basic_auth {
    username = sys.env("FM_USERNAME")
    password = sys.env("FM_TOKEN")
  }
  poll_interval = "1m"
}

clustering {
  enabled = true
}
```

## Imports and modules

Imported namespaces let you call user-defined components like stdlib functions.

```alloy
// Local file
import.file "utils" {
  filename = "./modules/utils.alloy"
}

// Git
import.git "k8s" {
  repository = "https://github.com/grafana/alloy-modules"
  revision   = "main"
  path       = "modules/kubernetes/"
}

// HTTP
import.http "shared" {
  url            = "https://config-server/alloy/shared.alloy"
  poll_frequency = "5m"
}

// Invoke an imported declare block
utils.my_component "example" {
  arg = "value"
}
```

`declare` defines a reusable component locally:

```alloy
declare "wrapped_scrape" {
  argument "target" { optional = false }
  argument "receiver" { optional = false }

  prometheus.scrape "inner" {
    targets    = [{__address__ = argument.target.value}]
    forward_to = [argument.receiver.value]
  }
}
```

## Durations and sizes

- Durations are Go-style strings: `"30s"`, `"1m"`, `"500ms"`, `"2h30m"`.
- Byte sizes use IEC/SI suffixes where accepted: `"512MiB"`, `"1GB"`.

## Common pitfalls

- **Quoting object keys** is required only when the key isn't a valid identifier (hyphens, dots,
  leading digits): `{"node-name" = "..."}`. Quoting Prometheus-style keys like `__address__` is
  conventional but not required.
- **Trailing commas** are allowed and recommended in multi-line arrays/objects.
- **Component labels** must match references exactly — `prometheus.scrape "api"` is referenced as
  `prometheus.scrape.api.<export>`, not `api.<export>`.
- **Forwarding** uses the recipient's input export — usually `.receiver` (Prometheus/Loki/Pyroscope)
  or `.input` (otelcol).
- **Reloads**: edit and `SIGHUP` the process, or POST `/-/reload` on the HTTP endpoint.
