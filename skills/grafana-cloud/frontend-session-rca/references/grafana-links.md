# Grafana deep links

Use Tempo URLs **only after the user picks a trace follow-up**. Session Replay `?t=` belongs on a **problem row** when a recording exists (seek to that problem’s timestamp). Do not invent Tempo Explore JSON.

`grafanaBase` is the stack origin with no trailing slash (from pasted session context or `gcx config view` → current context `grafana.server`). Sanitize: only `https:` (or `http:` for local Grafana). Never `javascript:` or `data:`.

Do not invent URLs. Omit a link when the field it needs is missing.

## Session in Frontend Observability

```
{grafanaBase}/a/grafana-kowl-app/apps/{appId}/sessions/{sessionId}
```

`appId` and `sessionId` are the values passed to `gcx frontend sessions get`.

## Session replay (web only)

Requires metadata `session_replay_start` (epoch ms) and a problem (or navigation) timestamp in ms.

```
{grafanaBase}/a/grafana-sessionreplay-app/app/{appId}/session/{sessionId}?t={offsetMs}
```

`offsetMs = problemTimeMs - session_replay_start`. Skip `?t=` when offset is not a finite number ≥ 0.

Skip this link when:

- The session is mobile (native SDK / no browser)
- `session_replay_start` is empty or `No data`
- The dump has no `faro.session_recording.started`

Do not call a replay manifest API. Do not claim the recording exists unless the dump says so.

## Tempo / traces

Keep `traceID` on the problem row as evidence. After the user asks to inspect it:

- Prefer `gcx traces get <id>` (that dump id only).
- A Tempo Explore URL only if the Tempo datasource UID is already known (pasted context or `gcx` datasource list). Never guess a UID. Never invent Explore pane JSON. If the UID is unknown, tell them to open **Explore → Tempo** and paste the id.

## What not to link

- Do not generate LogQL/SQL Explore URLs. The dump already has the session.
- Do not link mobile session replay (not available).
- Do not use plugin **repository** paths in user-facing text. Product names: Frontend Observability, Session Replay, Tempo.
