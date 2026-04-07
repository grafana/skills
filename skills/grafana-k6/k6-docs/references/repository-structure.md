# Repository Structure Reference

## k6-DefinitelyTyped

TypeScript type definitions:

```
types/k6/
├── browser/
│   └── index.d.ts          # Browser module types (Page, Frame, Locator, etc.)
├── http/
│   └── index.d.ts          # HTTP module types
├── test/
│   └── browser.ts          # Browser type tests
│   └── http.ts             # HTTP type tests
└── index.d.ts              # Core k6 types
```

## k6-docs

User-facing documentation:

```
docs/sources/k6/
├── next/                           # Upcoming release docs
│   └── javascript-api/
│       ├── k6-http/                # HTTP module docs
│       ├── k6-browser/             # Browser module docs
│       │   ├── page/
│       │   ├── frame/
│       │   ├── locator/
│       │   └── browsercontext/
│       ├── k6-grpc/                # gRPC module docs
│       └── k6-ws/                  # WebSocket docs
└── v1.X.x/                         # Released version docs
```

## k6

Main repository:

```
k6/
├── release notes/
│   └── v{VERSION}.md       # Release changelog
├── internal/js/modules/k6/
│   ├── http/               # HTTP module implementation
│   ├── browser/            # Browser module implementation
│   └── ...
└── lib/options.go          # Core k6 options
```

## Feature Type Mapping

| Type           | Example                          | Docs Location                       | Types Location              |
| -------------- | -------------------------------- | ----------------------------------- | --------------------------- |
| Core k6        | `check()`, `group()`, options    | `javascript-api/k6/` or `using-k6/` | `types/k6/index.d.ts`       |
| HTTP module    | `http.get()`, `http.batch()`     | `javascript-api/k6-http/`           | `types/k6/http/index.d.ts`  |
| Browser module | `page.click()`, `locator.fill()` | `javascript-api/k6-browser/`        | `types/k6/browser/index.d.ts` |
| gRPC module    | `grpc.Client`, `grpc.connect()`  | `javascript-api/k6-grpc/`           | `types/k6/grpc/index.d.ts`  |
| WebSocket      | `ws.connect()`                   | `javascript-api/k6-ws/`             | `types/k6/ws/index.d.ts`    |
| Experimental   | Redis, timers                    | `javascript-api/k6-experimental/`   | Various                     |
| CLI feature    | New flags, commands              | `using-k6/` or `misc/`              | N/A                         |

## How to Identify Feature Type

Use these three methods to determine which module a feature belongs to:

### Method 1: From PR/Commit Files

Look at which files are modified in the k6 repository:

- `internal/js/modules/k6/http/` → HTTP module
- `internal/js/modules/k6/browser/` → Browser module
- `internal/js/modules/k6/grpc/` → gRPC module
- `internal/js/modules/k6/ws/` → WebSocket module
- `lib/options.go` → Core k6 options
- `cmd/` → CLI features

### Method 2: From Feature Name

The method or class name often indicates the module:

- `page.waitForEvent` → Browser module (Page class)
- `http.asyncRequest` → HTTP module
- `--env` flag → CLI/Core feature
- `grpc.Client` → gRPC module

### Method 3: From Import Statement

Check the import statement in example code:

- `import { browser }` from `'k6/browser'` → Browser module
- `import http from 'k6/http'` → HTTP module
- `import { check } from 'k6'` → Core k6
- `import grpc from 'k6/grpc'` → gRPC module
- `import ws from 'k6/ws'` → WebSocket module

## Method tables in `_index.md`

It is **generally recommended** that method/API tables in `_index.md` files (e.g. in `javascript-api/k6-browser/page/`, `javascript-api/k6-http/`, or any module) be **sorted alphabetically** by method or API name. When adding a new method, add its row in the correct alphabetical position and create the corresponding method doc.