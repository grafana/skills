# TypeScript Definition Patterns

## Basic Method Signature

```typescript
/**
 * Brief description of what the method does.
 *
 * Additional context about when/why to use it.
 *
 * @example
 * ```js
 * // Example showing basic usage
 * const result = page.methodName('arg1');
 * ```
 *
 * @param paramName Description of the parameter.
 * @param options Options to use.
 */
methodName(
    paramName: string | RegExp,
    options?: {
        /** Description of option property. */
        timeout?: number;
    },
): Promise<ReturnType>;
```

## Method Overloads

For methods with different return types based on parameters:

```typescript
// Overload for string input
parse(input: string): ParsedString;

// Overload for buffer input
parse(input: ArrayBuffer): ParsedBuffer;

// Generic overload
parse(input: string | ArrayBuffer): ParsedString | ParsedBuffer;
```

## Browser Event Overloads

Event-based methods need per-event overloads for type safety:

```typescript
// Overload for 'console' event
waitForEvent(
    event: "console",
    optionsOrPredicate?: ((msg: ConsoleMessage) => boolean) | {
        predicate?: (msg: ConsoleMessage) => boolean;
        timeout?: number;
    },
): Promise<ConsoleMessage>;

// Overload for 'request' event
waitForEvent(
    event: "request",
    optionsOrPredicate?: ((req: Request) => boolean) | {
        predicate?: (req: Request) => boolean;
        timeout?: number;
    },
): Promise<Request>;
```

### When to Use Event Overloads

**Rule:** If a method accepts an event name string as the first parameter, create one overload per supported event.

**Why:** Each event type has its own return type (ConsoleMessage vs. Request vs. Response), so TypeScript needs explicit overloads to provide accurate type information.

**How to add a new event:**

1. Copy an existing overload
1. Change the event string literal: `"console"` → `"dialog"`
1. Update the parameter type in predicate: `ConsoleMessage` → `Dialog`
1. Update the return type: `Promise<ConsoleMessage>` → `Promise<Dialog>`

Example adding 'dialog' event:
```typescript
// Overload for 'dialog' event
waitForEvent(
    event: "dialog",
    optionsOrPredicate?: ((dialog: Dialog) => boolean) | {
        predicate?: (dialog: Dialog) => boolean;
        timeout?: number;
    },
): Promise<Dialog>;
```

**Note:** The `optionsOrPredicate` union type (function OR object) is a Playwright pattern that k6-browser mirrors.

## Type Tests

In `types/k6/test/<module>.ts`:

```typescript
// @ts-expect-error - Tests that required parameters are enforced
page.methodName();

// $ExpectType Promise<ReturnType>
page.methodName("argument");

// $ExpectType Promise<ReturnType>
page.methodName("argument", { timeout: 10000 });
```

Test patterns:
- `// @ts-expect-error` - Verifies TypeScript errors on invalid calls
- `// $ExpectType <Type>` - Verifies the return type

## Testing TypeScript Definitions

**IMPORTANT:** Use `pnpm` (not `npm`) to install dependencies. The k6-DefinitelyTyped workspace requires pnpm to create proper symlinks for module resolution.

```bash
cd k6-DefinitelyTyped
pnpm install -w --filter "{./types/k6}..."
pnpm test k6
```

Or use `${CLAUDE_PLUGIN_ROOT}/skills/k6-docs/scripts/test_typescript.sh`

The first command creates a symlink for `@types/k6` in `node_modules`, which is required for TypeScript module resolution to work during tests.

## Troubleshooting

### Error: `Cannot find module 'k6/browser'`

**Cause:** You likely used `npm install` instead of `pnpm install`.

**Fix:**
```bash
cd k6-DefinitelyTyped
pnpm install -w --filter "{./types/k6}..."
```

### Error: `dtslint is not found`

**Cause:** Missing workspace dependencies.

**Fix:**
```bash
cd k6-DefinitelyTyped
pnpm install -w --filter "{./types/k6}..."
```

Ensure you're using the `--filter` flag with the workspace flag `-w`.

### Pre-existing Test Failures

**Context:** The test suite may have pre-existing failures unrelated to your changes.

**Action:** Focus on ensuring your NEW types don't introduce ADDITIONAL errors. Compare test output before and after your changes.

See [Troubleshooting guide](troubleshooting.md) for more help.

## Formatting

Format files with dprint:

```bash
pnpm dprint fmt types/k6/
```

Or use `${CLAUDE_PLUGIN_ROOT}/skills/k6-docs/scripts/format_typescript.sh`
