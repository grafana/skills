# Workflow elicitation — verbatim question script

Read the questions below to the user **before scaffolding anything**.
Capture answers in a `runbook.md` in the target project directory.
Every later step depends on these answers.

If the user can't or won't answer the workflow question (Q1), stop
and clarify. Do not guess workflows.

---

## Question script

Read these in order. Adapt phrasing only if the user has already
volunteered an answer.

### Q1. Workflows

> Before we write any code, I need you to name the workflows you want
> covered. Think of a workflow as a single connected sequence of user
> actions that produces a measurable outcome — for example, "log in,
> add an item to the cart, check out", or "open the admin dashboard
> and approve a pending request".
>
> Please give me **2 to 4 workflows**, each with:
> - A short name (e.g. "checkout", "admin-approve", "anon-search").
> - A one-sentence description of what the user does.
> - Whether it requires authentication.

### Q2. Credentials

> For any auth-required workflow above, please provide test
> credentials. These should be:
> - **Dedicated test accounts**, not real users.
> - Allowed to perform the workflow's write actions safely (no real
>   payments, no real data deletion).
>
> If you don't have test accounts yet, we need to pause and have you
> create them before continuing.

### Q3. Read vs write

> For each workflow, is it read-only, or does it write data to the
> backend? Examples:
> - Browsing a catalogue → read-only.
> - Posting a comment, placing an order, updating a profile → write.

### Q4. Destructive actions

> Are there any actions in your workflows that would be destructive
> if repeated thousands of times during a soak run? Common examples:
> - Payments (real money or test-card limits).
> - Account creation (DB bloat, email-vendor rate limits).
> - Sending notifications to real users.
> - Deletion of real data.
>
> List them and we'll either skip them in soak or substitute with a
> dry-run endpoint.

### Q5. Worry list

> Which one workflow do you most worry about under load? This is the
> one we'll spend the most time tuning thresholds on.

### Q6. Existing SLOs

> Do you already have SLOs in mind for this app? Please share:
> - Latency target (e.g. "p95 < 500ms").
> - Error rate target (e.g. "< 0.1% error").
> - Throughput target (e.g. "100 req/s sustained").
>
> If you don't have specific numbers, we'll use sensible defaults and
> tune after smoke.

### Q7. Backend ownership

> Do you own the backend serving this website, or only the front
> end? If you own it, do you have Grafana access (or equivalent
> observability)?
>
> If yes, please tell me:
> - Grafana URL.
> - Service name / labels used in your metrics.
> - Whether Prometheus, Loki, Tempo, Pyroscope are all configured
>   (or which subset).

### Q8. Per-test-type local vs cloud

> k6 supports six test types. For each, we need to decide whether
> to run it locally on your laptop or in Grafana Cloud k6. The
> tradeoffs are:
>
> - **Local**: free, but a single laptop usually can't drive enough
>   load to hit a production website's ceiling. Good for validating
>   that scripts behave correctly.
> - **Grafana Cloud k6**: scales horizontally so you can actually
>   reach the ceiling. Free tier is finite. **Browser VU-hours are
>   billed 10× protocol VU-hours.** Soak and breakpoint are the
>   most likely to exhaust budget.
>
> Where would you like to run each test type?
>
> - smoke (<1 min, low VUs, sanity check):  local / cloud / both / skip
> - average (expected production load):     local / cloud / both / skip
> - stress (beyond expected, find cliff):   local / cloud / both / skip
> - spike (sudden VU jump):                 local / cloud / both / skip
> - soak (sustained, find leaks/drift):     local / cloud / both / skip
> - breakpoint (find ceiling):              local / cloud / both / skip

### Q9. Target URL and constraints

> What's the target URL? Are there:
> - IP allow-lists that might block Grafana Cloud k6 LGs?
> - Rate-limiters / WAFs that might throttle tests?
> - Maintenance windows or off-peak times we should target?
> - Any CDN edge nodes we should avoid hitting (a static asset CDN
>   used to keep an SLO honest, but not the system-under-test)?

### Q10. Run plan sign-off

After capturing Q1-Q9, write a `runbook.md` summarising:

```markdown
# Run plan — <site>

## Workflows
1. **wN-<short-name>** — <description> (read-only / write, auth: yes/no)
2. ...

## Credentials
- wN: provided / will be provided / not required

## Destructive actions
- ...

## SLOs
- Latency: ...
- Error rate: ...
- Throughput: ...

## Backend ownership
- Owns backend: yes / no
- Grafana: <url>
- Service labels: ...
- Datasources: Prom / Loki / Tempo / Pyroscope

## MCP tools planned for this project
List the MCP tools you'll lean on at each step. Spelling them out
in the runbook makes the rest of the workflow self-checking — if
you scaffold without an `mcp-k6` step but the runbook says you'll
use it, that's a flag to come back and not handwrite the migration.

- HAR → k6 protocol conversion: `npx har-to-k6` (CLI, always)
- Playwright recorder → k6/browser migration: `mcp-k6` if installed,
  otherwise the 5-step procedure in `references/functional-tests.md`
- k6 script authoring / validation: `mcp-k6` if installed
- Backend investigation (if backend is owned): `mcp-grafana` if
  installed, otherwise `gcx` CLI; see `references/grafana-investigation.md`

## Run matrix
| Test type   | Where                |
|-------------|----------------------|
| smoke       | local / cloud / both / skip |
| average     | ...                  |
| ...         | ...                  |

## Constraints
- IP allow-list: ...
- Rate limiters: ...
- Maintenance windows: ...
```

Then read it back to the user and ask:

> "Does this run plan look right? Anything to add or change before
> we scaffold?"

Only proceed to §2 of the SKILL after the user explicitly confirms.

---

## Common deflections and how to handle them

- **"Just figure out the workflows from the website."** → Decline.
  Workflows encode the user's business priorities; the test results
  only matter if the workflows reflect what real users do. Push
  back: "Tell me the 2-4 paths your users hit most often, or the
  ones that worry you most."
- **"Test everything."** → Decline. Decompose into named workflows.
  "Everything" is not testable; named paths are.
- **"I'll add SLOs later."** → Accept, but record sensible defaults
  in §10's run plan and flag them as "default, pending user
  confirmation" so the final report can call out the assumption.
- **"Just use cloud for everything."** → Confirm budget awareness:
  re-read the cost reminder from Q8, then proceed.
- **"Just use local for everything."** → Note that you may not reach
  the ceiling. Flag in the run plan: "local-only — results bounded
  by LG capacity".
