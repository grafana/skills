---
name: frontend-session-rca
license: Apache-2.0
description: >
  Diagnoses a Grafana Frontend Observability (RUM) session: whether it is healthy,
  what went wrong, ranked problems with timestamps and evidence, likely cause, how
  to fix it. Optional follow-up: zoom in on the top error, impact across sessions,
  Session Replay, or a Tempo trace if the user asks.
  Fetches telemetry with `gcx frontend sessions get --save` and reads only that dump
  file.
  Use when the user asks to explain, diagnose, analyse, RCA, or review a session;
  asks if a session is healthy; pastes Frontend Observability session context (app
  id, session id, datasource UID); or mentions Faro, user journey, Core Web Vitals,
  exceptions, ANR, or a web or mobile RUM session — even if they do not say
  "session narrator" or "frontend-session-rca". Do not use this skill to instrument
  an app (Faro Web, React Native, Flutter, native OpenTelemetry) — use
  `app-observability` for Faro Web setup
  in this grafana-cloud plugin.
---

# Frontend Observability session RCA

Diagnose one real-user session from a `gcx` dump. First answer is dump-only. Do not invent LogQL, SQL, or Explore URLs. Do not instrument SDKs here.

## 1. Collect identity

Required — do **not** fetch until all three are present:

- **app id**
- **session id**
- **datasource UID** (`-d`) — Grafana datasource UID, not `loki` or `pinot`

Take them from the prompt or pasted Frontend Observability session context. If any required field is missing, **ask the user and stop**. Do not guess ids. Do not pick a datasource for them (you may mention `gcx datasources list` so they can choose a Loki or Pinot UID). In that same ask, say the time-range default below so they can override it in one reply.

Optional: Grafana stack URL, `--app-type web|mobile`, time range.

Time range is **not** required. If the user did not give `--from`/`--to` or `--since`, tell them:

> We will run the query for 1d for Loki and 7d for Pinot. If you want a different time range, please provide it.

Then infer Loki vs Pinot from the UID (`gcx datasources get <uid>`) and pass `--since 1d` (Loki) or `--since 7d` (Pinot). If they already gave a window, use that (`--from`/`--to` and `--since` are mutually exclusive).

## 2. Ensure gcx

```bash
command -v gcx && gcx frontend sessions get -h
```

| Result | Action |
|---|---|
| `gcx` missing | Tell the user to install from https://github.com/grafana/gcx (`brew install gcx` or the curl installer on that README). If a `setup-gcx` skill is already loaded, use it instead of duplicating the tutorial. Do not invent tokens. |
| `gcx` present, `sessions get` unknown | Installed gcx is too old. Tell the user to upgrade gcx, then retry. |
| Command exists | Continue. |

Unauthenticated:

```bash
gcx login --server <grafana-stack-url>
```

Grafana base URL (for deep links), if the user did not paste one:

```bash
gcx config view -o json
```

Use the current context `grafana.server`. Do not print tokens.

## 3. Fetch the session

Always `--save` so stdout is a small artifact receipt (path only), not the dump.

```bash
gcx frontend sessions get <session-id> \
  --app <app-id> \
  -d <datasource-uid> \
  --since 1d \
  --save /tmp/session-<session-id>.txt
```

- `-d/--datasource` is required (Grafana datasource UID). Do not pass `loki` or `pinot` as the value. gcx infers the type from the datasource.
- Time range: use the user’s `--from`/`--to` or `--since` when they gave one. Otherwise `--since 1d` (Loki) or `--since 7d` (Pinot) after telling them the default (see step 1).
- Omit `--app-type` unless the user set it; gcx infers web vs mobile from the dump.
- Agent mode requires `--save`. If stdout is JSON `gcx.artifact_receipt`, read `files[0].path`. If stdout is `Wrote <path>`, read that path.

Never paste the dump into the user-visible reply.

## 4. Read the dump, then answer

1. Open the file. Parse `=== session metadata ===` then `=== events ===`. See [dump-format.md](references/dump-format.md).
2. Classify health and rank issues using [signal-catalog.md](references/signal-catalog.md).
3. Follow-up is 1–3 questions, not a link dump (see template). Do not attach Tempo URLs to every problem. Do not call a replay API.

**Empty or failed fetch:** say so. Suggest widening `--since` / `--from`/`--to`, checking `--app` and `--datasource`, and confirming the user can see the session in Frontend Observability. Stop.

**Specific question** (one error, one page, one trace, “why is LCP poor”, “why was cold start slow”, “other sessions with this error”): answer that. Skip the full template. Dump-only unless they asked for impact or a trace — then a scoped `gcx logs` / `gcx traces get` is allowed.

**Vague “diagnose / explain this session”:** use the template below.

## Full-session template

```markdown
## Session overview
- App, session id, web or mobile, duration (`session_start` event → last event in this window as `session_end`; end is not a Faro event)
- Environment: browser/OS or device/SDK, geo, app version, user if present
- Outcome: **healthy** | **degraded** | **error** | **unknown**

## What the user did
3–6 sentences of the journey in time order, oldest first (navigation, views, actions). No raw dump.

## Session health
One paragraph: healthy or not, and why (exceptions, failed HTTP, poor web vitals or mobile startup/jank, ANR, rage clicks).

## Problems found
Ranked list. Each item:
- Severity: critical / warning / info
- Timestamp (from the dump)
- What happened (exception type/message, HTTP status+URL, web vital or mobile cold/warm start / jank, …)
- Lead-up: the 1–3 events immediately before it
- `traceID` if that row has one (the id only — not a Tempo URL)
- Session Replay at this timestamp — only web + `session_replay_start`; `?t=` = problem time − recording start ([grafana-links.md](references/grafana-links.md)). Omit on mobile, if there is no recording, or if `t < 0`.

## Likely cause
One or two sentences citing dump evidence. If several independent issues, say so — do not force a single root cause.

## How to fix it
Concrete next engineering steps (code, config, backend, or telemetry gaps). See [signal-catalog.md](references/signal-catalog.md).

## Follow-up
- <1–3 short questions named from this dump>
```

Fill Follow-up from this list, in order, **omitting** any line the dump cannot support (max 3). Write them as questions, with the concrete error / hash / page / `traceID`:

1. **Zoom in** — walk through the top critical issue at its timestamp (if there is a ranked problem).
2. **Impact** — other sessions in the last 24h/7d with this exception `hash` (or type+template), and which `app_version`s? Say this needs a second query. Skip if there is no stable hash/type (one-off `status=0`, vital without `page_id`).
3. **Trace** — pull the backend trace for this `traceID`? Only if that problem has one.

Do not offer “open this session in Frontend Observability” or “watch replay” (replay seek is on the problem row when a recording exists). Do not put Tempo on every problem. Do not guess impact counts from this dump.

## Grounding rules

- Narrate the first answer only from the dump. If a field is missing, say it is missing.
- After the user picks **impact**: scoped `gcx logs query` for that exception `hash` or type+template, this `--app`, and a time window. Do not invent Explore LogQL URLs. Do not state other-session counts until that query returns.
- After the user picks **trace**: `gcx traces get <id>` for that dump `traceID` only — not a new session-wide query. Tempo Explore URL only if the Tempo datasource UID is known; never guess UID or pane JSON.
- Prefer the dump’s `rating` on web vitals over recomputing thresholds. On mobile, use startup/jank fields as present.
- Do not claim session replay or video unless `faro.session_recording.started` / `session_replay_start` is in the dump.
- Do not write `gcx frontend sessions get` as something the Grafana UI runs. This skill is the only place that command is documented for agents.

## References

- [dump-format.md](references/dump-format.md) — metadata vs events blocks, Loki vs Pinot
- [signal-catalog.md](references/signal-catalog.md) — health, ranking, thresholds, remediations
- [grafana-links.md](references/grafana-links.md) — replay `?t=` on problems, Tempo on trace follow-up
