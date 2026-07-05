# TypeScript Definitions Checklist

## Type Definitions

- [ ] JSDoc comments: Clear description, @example with code, @param descriptions
- [ ] Method signature: Correct parameter types, return type, optional params marked with ?
- [ ] Overloads: If method has different return types, are overloads defined?
- [ ] Consistency: Matches style of existing methods in same interface

## Type Tests (in types/k6/test/)

- [ ] Coverage: All method signatures tested
- [ ] @ts-expect-error: Tests for invalid calls
- [ ] $ExpectType: Return types verified for each overload

## Testing

Run each command separately:
1. `pnpm install -w --filter "{./types/k6}..."`
2. `pnpm test k6`

Pre-existing failures may exist - focus on new types not introducing errors
