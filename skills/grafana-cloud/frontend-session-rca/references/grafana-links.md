# Grafana deep links

Use Tempo URLs **only after the user picks a trace follow-up**. Session Replay `?t=` belongs on a **problem row** when a recording exists (seek to that problem’s timestamp). Do not invent Tempo Explore JSON.

`grafanaBase` is the stack origin with no trailing slash (from pasted session context or `gcx config view` → current stack `grafana.server`). Sanitize: only `https:` (or `http:` for local Grafana). Never `javascript:` or `data:`.

Do not invent URLs. Omit a link when the field it needs is missing.

## Session in Frontend Observability

```
{grafanaBase}/a/grafana-kowalski-app/apps/{appId}/sessions/{sessionId}
```

`appId` and `sessionId` are the values passed to `gcx frontend sessions get`. Do not invent a `?tracesQuery=` pane JSON; the session page works without it.

## Session replay (web and mobile)

Same link for a browser recording and a mobile video recording. The app sends a Faro event named `faro.session_recording.started` (not `session_replay_start`, not `session_replay.start`). gcx copies that event’s timestamp into metadata as `session_replay_start` and does not require the event row to remain in `=== events ===`. When that row is present, use its client `timestamp=` as the recording clock and the problem row’s `timestamp=` as the problem time (the metadata integer is the Loki line time and can be seconds later than the frame the player seeks). Otherwise use metadata `session_replay_start`. gcx does not always print those as epoch ms: Loki is usually 19-digit ns; Pinot is RFC3339.

Convert **both** to epoch ms first ([dump-format.md](dump-format.md) Timestamps). Then:

```
{grafanaBase}/a/grafana-sessionreplay-app/app/{appId}/session/{sessionId}?t={offsetMs}
```

`offsetMs = problemTimeMs - replayStartMs`. That offset is where the Session Replay player puts the playhead: into the rrweb timeline on web, or into the mobile video clip. Skip `?t=` when either conversion fails or offset is not a finite number ≥ 0. Treating a Loki ns value as ms makes `t` negative.

On each problem row, render one markdown link, not a bare URL:

```
[Open session replay at this moment]({grafanaBase}/a/grafana-sessionreplay-app/app/{appId}/session/{sessionId}?t={offsetMs})
```

Skip this link when `session_replay_start` is missing, empty, or `No data`. Do not also require an events-block row named `faro.session_recording.started`, `session_replay_start`, or `session_replay.start`.

Do not skip because the session is mobile, native, or has no browser fields. A mobile dump with `session_replay_start` has a recording.

When `offsetMs` is a finite number ≥ 0, the link can be built. Before writing it, GET the player URL once, without following redirects:

```bash
curl -s -o /dev/null -w '%{http_code}' --max-redirs 0 \
  "{grafanaBase}/a/grafana-sessionreplay-app/app/{appId}/session/{sessionId}"
```

HTTP 200: the link is required on every problem row with a valid `offsetMs`. Any other status: omit the links. Do not call a replay manifest API. Do not claim the recording exists unless the dump says so.

## Tempo / traces

Keep `traceID` on the problem row as evidence. After the user asks to inspect it:

- Prefer `gcx traces get -d <tempo_uid> <trace_id>` (that dump id only). `-d` is required unless `datasources.tempo` is already in the gcx context.
- A Tempo Explore URL only if the Tempo datasource UID is already known (pasted context or `gcx` datasource list). Never guess a UID. Never invent Explore pane JSON. If the UID is unknown, tell them to open **Explore → Tempo** and paste the id.

## What not to link

- Do not generate LogQL/SQL Explore URLs. The dump already has the session.
- Do not invent a mobile replay link when `session_replay_start` is missing. When that field is present, link it the same way as web.
- Do not use plugin **repository** paths in user-facing text. Product names: Frontend Observability, Session Replay, Tempo.
