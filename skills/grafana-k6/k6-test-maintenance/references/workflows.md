# Maintenance workflows

Step-by-step procedures for the five maintenance tasks. All apply the
behaviour-aware change control, mandatory validation, and post-edit
verification defined in `SKILL.md`; verification recipes are in
[`verification.md`](verification.md).

## Contents

- [Threshold tightening](#threshold-tightening)
- [Version migration](#version-migration)
- [Service change adaptation](#service-change-adaptation)
- [Refactoring](#refactoring)
- [Best practices audit](#best-practices-audit)

## Threshold tightening

Typically triggered by `k6-trend-analysis` recommendations or user request.

### Step 1: Understand the current state

Gather the inputs:
- The current script (cloud or local)
- The current threshold definitions
- Trend data or metric observations that motivate the change (from
  `k6-trend-analysis` output, user-provided data, or fresh metric queries
  via `k6-manage`)

### Step 2: Propose new threshold values

For each threshold being tightened:
- State the **current value** and the **proposed value**
- Show the **observed metric** that justifies the change (e.g., "P95 is
  currently 380ms, proposing p(95)<450 to give 18% headroom")
- Note any **downstream impact**: does this threshold have `abortOnFail`?
  Is it referenced in CI gates or SLO definitions?

### Step 3: Present the diff

Show a clear before/after diff of the `thresholds` block. This is a
behavioral change -- always wait for user confirmation.

### Step 4: Apply and verify

After confirmation:
1. Apply the change to the script
2. Validate: `k6 inspect` (parse check) or `validate_script` (mcp-k6)
3. For cloud-hosted scripts, follow k6-manage Section 5 safe-edit recipe
   (backup → PUT → sha256-verify)
4. **Verify per the verification matrix in `SKILL.md`.** Threshold
   changes are Class A -- use the historical pass/fail prediction recipe
   ([`verification.md` § Class A](verification.md#class-a-historical-passfail-prediction)).
   For loosening, the prediction table also surfaces which past failing
   runs are being "hidden" by the change, which the user should see
   before the PUT.
5. Confirm the change was applied.

## Version migration

Triggered when the user wants to update a script for a new k6 release, or when
deprecated APIs are detected.

### Step 1: Identify what needs migration

Read the script and look for:
- Deprecated imports (e.g., `k6/ws` → `k6/experimental/websockets`)
- Removed or renamed APIs
- Changed option formats (e.g., `ext.loadimpact` → `cloud`)
- Patterns that have newer alternatives

Use documentation to confirm migrations:
1. Check mcp-k6 `get_documentation` for migration guides (preferred)
2. Fall back to `k6 x docs using-k6 javascript-api` for API reference
3. Last resort: web fetch from `https://grafana.com/docs/k6/latest/`

### Step 2: Classify each change

For each required migration:
- **Is the API identical after the import swap?** (e.g., same function
  signatures, same behavior) → syntactic change, can auto-apply
- **Does the API differ?** (e.g., different method names, new patterns
  required) → behavioral change, must propose and confirm

### Step 3: Apply syntactic changes

Auto-apply all purely syntactic migrations (import path swaps where the API
surface is identical). Show a summary of what was changed.

### Step 4: Propose behavioral changes

For each migration that changes behavior:
- Show the old pattern and the new pattern side by side
- Explain what differs in behavior
- Cite the documentation source

Wait for user confirmation before applying each one.

### Step 5: Validate and verify

After all changes are applied:
1. Run `k6 inspect` or `validate_script` to confirm the script parses
2. **Verify per the verification matrix in `SKILL.md`.** Migration
   edits are Class B by definition (imports and APIs changed), so choose
   the short-vs-long-test path based on the saved test's expected
   duration. Don't skip the cloud smoke for long tests just because the
   change "looks like a rename" -- migration bugs often hide in
   cloud-only behaviour (load-zone connectivity, env-var resolution).
3. Present the verification result.

## Service change adaptation

Triggered when a test starts failing because the underlying service changed
(new endpoints, different response schema, changed auth), or when
`k6-cloud-investigate-test` hands off after identifying a service-side cause.

### Step 1: Understand what changed

Gather evidence of what changed on the service side:
- If coming from `k6-cloud-investigate-test`: read the investigation report
  for the specific failure details (error messages, status codes, response
  bodies)
- If the user describes the change: confirm the specifics (what endpoint
  changed, what the new behavior is)
- If neither: fetch the most recent failing run's logs via `k6-manage`
  Section 4 and compare with the last passing run to identify the delta

### Step 2: Categorize the changes needed

Map each service change to a script change:

| Service change | Script impact | Complexity |
|---------------|--------------|------------|
| Endpoint URL changed | Update URL string | Simple if new URL known |
| Response field renamed | Update check assertions | Moderate |
| New required header/param | Add to request config | Moderate |
| Auth mechanism changed | Rewrite auth flow | Complex |
| Response schema restructured | Rewrite extraction + checks | Complex |
| Endpoint removed/replaced | Rewrite entire request | Complex |

### Step 3: Propose fixes

For each change:
- Show the current failing code and the proposed fix
- Explain the rationale (what changed on the service side)
- All of these are behavioral changes -- present as a diff with rationale

For complex changes where the "right" fix depends on user intent:
- Present multiple options if applicable
- Flag what you're uncertain about
- Ask the user to clarify before proceeding

### Step 4: Validate and verify

After confirmation and applying changes:
1. Validate with `k6 inspect` or `validate_script`
2. **Verify per the verification matrix in `SKILL.md`.** Service-change
   fixes are Class B (request URLs, check predicates, or auth flow
   changed). The cloud smoke is especially important here -- a fix that
   works locally against your laptop's network may still hit the wrong
   host or fail auth from cloud load zones.
3. Confirm the previously-failing checks now pass against the new
   service shape.

## Refactoring

Triggered by user request to clean up or modernize a test script.

### Step 1: Read and analyze the script

Look up best practices in the docs before analyzing -- don't rely on model
knowledge alone. Run `k6 x docs using-k6-browser/recommended-practices` for
browser tests, `k6 x docs using-k6 thresholds` for threshold patterns, etc.

Identify issues:
- Dead code (unused variables, unreachable branches)
- Duplicated logic that could be extracted to helper functions
- Overly complex structure that could be simplified
- Inconsistent naming or patterns
- Missing error handling (e.g., no `try/finally` for browser tests)
- Deprecated patterns (e.g., `waitForNavigation`, `networkidle`, `type()`
  instead of `fill()`)
- Async bugs (e.g., async methods inside sync `check()` predicates)
- Missing thresholds or performance guards

Be thorough. The user asked for a refactor -- find everything, even if some
findings are behavioral. The classification framework exists to handle this:
you'll auto-apply the syntactic ones and propose the behavioral ones. Don't
self-censor by leaving out findings you're unsure about -- classify them and
let the user decide.

### Step 2: Classify each change

Apply the behavior-aware rule:
- **Syntactic** (auto-apply): variable renames, `let` → `const`, remove
  unused imports, reformat, add/update comments, extract pure helper functions
  that don't change call semantics
- **Behavioral** (propose + confirm): adding `try/finally` error handling,
  restructuring scenarios, changing group boundaries, extracting logic that
  changes execution order

### Step 3: Apply and propose

1. Auto-apply all syntactic changes to the output script
2. Do NOT apply behavioral changes to the output script -- describe them in
   the report as proposals with diffs and rationale
3. The output script should reflect ONLY syntactic fixes so the user can see
   what was safely changed vs what needs their approval
4. Run `k6 inspect` on the output script to validate it

### Step 4: Apply behavioral changes after confirmation

Once the user confirms, apply behavioral changes, re-validate, then
**verify per the verification matrix in `SKILL.md`**. A refactor that
"shouldn't change behaviour" still needs Class B verification because the
classification is about the diff, not the intent -- if any runtime byte
changed, treat it as Class B.

## Best practices audit

Triggered by user request, or as a secondary check during any other maintenance
workflow. Uses documentation to identify improvements.

### Step 1: Establish the documentation source and look up best practices

This step is not optional. Look up documentation before auditing -- do not
rely solely on model knowledge.

Try in order:
1. **mcp-k6**: call `get_documentation` for best practices
2. **`k6 x docs`**: run `k6 x docs using-k6` for general guidance, then
   topic-specific lookups as needed (e.g.,
   `k6 x docs using-k6-browser/recommended-practices` for browser tests)
3. **Web fetch**: `https://grafana.com/docs/k6/latest/` as last resort

For browser tests specifically, look up:
- `k6 x docs using-k6-browser/recommended-practices`
- `k6 x docs javascript-api k6-browser page`
- `k6 x docs javascript-api k6-browser locator`

### Step 2: Audit the script

Check against these categories:

**Thresholds and assertions:**
- Are thresholds defined? (At minimum: `http_req_duration` and
  `http_req_failed` for HTTP tests)
- Are `check()` or `expect()` assertions on every response?
- Are thresholds realistic based on the test type?

**Load design:**
- Is `sleep()` present in load tests? (Required for realistic think time)
- Are scenarios using appropriate executors for the test type?
- Is the VU/iteration count reasonable?

**Resource management:**
- Browser tests: `try/finally` with `page.close()` in `finally`?
- gRPC tests: `client.close()` after each iteration?
- File handles and connections properly closed?

**Code quality:**
- `const` instead of `let`/`var` at module level?
- No deprecated imports?
- No hardcoded secrets? (Should use `__ENV` or environment variables)
- SharedArray for test data files?

**Browser-specific** (if script imports `k6/browser`):
- Using `getBy*` APIs (`getByRole`, `getByLabel`, `getByText`,
  `getByTestId`) instead of generic `page.locator()` where possible?
- Not calling `waitFor()` before interactions (built-in actionability)?
- Not using `waitForLoadState()` after navigation?
- Using `page.waitForTimeout()` instead of `sleep()` in browser context?

### Step 3: Present findings

Produce an audit report:

```markdown
## Best Practices Audit: {script_name}

### Passed
- [x] Thresholds defined
- [x] Checks on responses
- [x] sleep() between iterations

### Needs attention (behavioral changes -- requires confirmation)
- [ ] **Add try/finally for browser cleanup**: page.close() is not in a
      finally block. If a test step throws, the browser page leaks.
      [Doc: k6 x docs javascript-api k6-browser page]
- [ ] **Use getByRole instead of locator**: 3 instances of
      page.locator('input[name="..."]') could use getByRole('textbox').
      [Doc: k6 x docs javascript-api k6-browser locator]

### Auto-applied (syntactic -- no behavior change)
- [x] Changed 2 `let` declarations to `const` (lines 12, 45)
- [x] Removed unused import `encoding` (line 3)
```

### Step 4: Produce the output script

Apply syntactic changes to a copy of the script and save it. Behavioral
changes should be described in the report but NOT applied to the output
script -- they are proposals awaiting confirmation. The output script should
contain only the syntactic (auto-applied) fixes so the user can see the
safe changes separately from the proposed behavioral ones.

Run `k6 inspect` on the output script to validate it parses correctly.

### Step 5: Apply behavioral changes after confirmation

Once the user confirms specific behavioral changes, apply them to the script,
re-validate, and **verify per the verification matrix in `SKILL.md`**.
Audit-driven changes are Class B by default.
