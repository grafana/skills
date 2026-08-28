# Session dump format

`gcx frontend sessions get --save` writes a plain-text file (not JSON, not YAML).

```
=== session metadata ===
<identity and envelope, once>

=== events ===
<events, oldest first>
```

Read **metadata first** (device, user, geo, span, recording start), then **events** (timeline). Envelope fields are not repeated on every event by design.

## Metadata

Typical fields (names vary slightly Loki vs Pinot; use whatever is present):

| Field | Use |
|---|---|
| `app_name`, `app_version`, `app_environment` | What shipped |
| `sdk_name`, `sdk_version` | Web vs mobile (`@grafana/faro-web-sdk` vs RN/Flutter/native) |
| `browser_*` | Web only |
| `os_*`, `device_*` | Mobile (and sometimes web OS) |
| `geo_*` | Location if collected |
| `user_id`, `user_username`, `user_email` | User if set |
| `session_id` | Session id |
| `session_start` | Timestamp of the Faro **`session_start` event** (`kind=event`, `name=session_start`). That is a real lifecycle event. It is **not** necessarily the first row in the events block (other telemetry can precede it). If that event is missing from this `--from`/`--to` window, say so — do not invent a start from the first dump row. |
| `session_end` | **Not** a Faro event. Last event timestamp in this `--from`/`--to` window (`max(timestamp)` of what gcx returned). Do not treat “last event time ≠ `session_end`” as truncation — they are the same. |
| `session_replay_start` | Epoch ms of `faro.session_recording.started`. Empty = no replay. |

Pinot metadata may print as tables. Loki metadata is `key=value` lines. Treat both as a single bag of fields.

gcx already infers web vs mobile when `--app-type` is omitted. Do not re-derive `--app-type`. Use `sdk_name` / browser vs device fields as they appear for the narrative.

## Events

Rows are **oldest first** (ascending timestamp). Pinot: `ORDER BY "timestamp" ASC`. Loki: `direction=forward`, then sorted by timestamp.

**Loki:** one line per event: timestamp, then the log line with envelope keys stripped. Parse `kind`, `name` (events), `type` (measurements), status, URL, message, `traceID` / `trace_id`. Measurement values are `value_<key>` — the same keys the SDKs put in `values` (`value_lcp`, `value_appStartDuration`, `value_coldStart`, `value_slow_frames`, `value_frozen_frames`, …).

**Pinot:** tab-separated values with a header row. Use whatever headers are present; they describe the same Faro payload (`kind`, measurement `type`, HTTP, exception, navigation). Do not assume Pinot-only column aliases.

`kind` values you will see: `event`, `exception`, `measurement`, `log` (and sometimes others). Ignore high-volume performance-entry noise if it still appears.

### Timestamps

- 13-digit integer → epoch **ms**
- 19-digit integer → epoch **ns** (divide by 1e6 for ms)
- RFC3339 → parse to ms

Replay offset: `t = problemTimeMs - session_replay_start` (both ms). If `t < 0`, skip the `?t=` query param.

The dump has no truncated / incomplete flag (`--no-truncate` is table-column display only). Narrate the events gcx returned for that `--from`/`--to`. Empty dump or gcx error: stop (see the skill). Do not invent events.
