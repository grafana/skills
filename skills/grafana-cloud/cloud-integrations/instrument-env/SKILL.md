---
name: instrument-env
license: Apache-2.0
description: >
  Install and configure Grafana Alloy to instrument the software discovered by the
  enumerate-environment skill, shipping metrics and logs to Grafana Cloud. Takes the
  environment inventory as a starting point (Linux / non-Kubernetes hosts are the primary
  flow), sets up a Grafana Cloud access policy token, discovers the target stack via gcx,
  installs Alloy per host with the official onboarding script, applies the pre-built
  Grafana Cloud integrations (linux-node plus one per detected application), and summarizes
  the result. Use when the user asks to instrument an environment or host, install or
  deploy Alloy, set up monitoring for discovered services, send metrics/logs to Grafana
  Cloud, close the coverage gaps found by enumerate-environment, or create a telemetry
  token. Triggers on phrases like "instrument my environment", "install alloy", "set up
  monitoring", "ship metrics to Grafana Cloud", "fix the coverage gaps".
---

# Instrument Environment

Take the inventory produced by the `enumerate-environment` skill and close its
missing-collector gaps: install Grafana Alloy where it is absent, configure it with the
pre-built Grafana Cloud integrations matching the services actually running there, and ship
metrics and logs to **Grafana Cloud**.

**This skill mutates the environment.** Installs, service config changes, and restarts all
happen on the user's hosts — each prompt below is a hard gate; never proceed past one on an
assumed answer, never modify or restart an existing collector without confirmation, and
never emit raw credentials — tokens are written to config files, not chat.

The workflow below is the primary flow and targets **Linux, non-Kubernetes hosts** (bare
metal, Multipass or other VMs). Kubernetes and Docker Compose paths are not yet specified —
see [Future work](#future-work-tbd).

## Step 1 — Obtain the environment inventory (prompt if missing)

Use the most recent `enumerate-environment` output available in the conversation or a saved
report file. **If none exists, prompt the user**: run `enumerate-environment` now, or cancel
`instrument-env`. Those are the only two options — the inventory (hosts, software per host,
Alloy coverage) is required input and there is no manual fallback.

From the inventory, extract the work list: each Linux host to instrument and the
applications enumerated on it (e.g. the host itself plus a pgbouncer service).

<!-- TODO(research): define the exact inventory fields consumed, and the precedence rule
     between "extend existing Alloy" vs "install new" -->

## Step 2 — Verify gcx login and obtain the Alloy token (prompt)

Two prerequisites, both supplied by the user:

**1. gcx login.** Run `gcx config check`: a valid, online context (✔ Configuration /
✔ Connectivity) is required so Step 3 can discover the stack details. If no context passes
the check, the user is not logged in — the prompt asking them to set up gcx **must include
this link to the login instructions**:
<https://github.com/grafana/gcx/blob/74fff38ba3e8f7f9d7529ea7690fdfe905a1713a/docs/reference/login.md>
— they need to `gcx login` and attach a Cloud Access Policy token with the scopes listed
in that doc (`stacks:read` is the required baseline). General gcx setup lives at
<https://github.com/grafana/gcx>.

**2. Alloy token.** Alloy needs a Grafana Cloud **access-policy token** scoped to
`metrics:write`, `logs:write`, `traces:write`, `profiles:write`, `fleet-management:read`.
**Prompt the user to provide one** — they create it manually in the Grafana Cloud portal
(see [references/grafana-alloy-token-guide.md](references/grafana-alloy-token-guide.md),
Option A). Ask them to place it in a mode-600 env file (e.g.
`~/.config/gcx/alloy-token.env` containing `GCLOUD_RW_API_KEY=…`) rather than pasting it
into chat; never echo a token value back into the conversation — confirm receipt and move
on. Operational details in [references/tokens.md](references/tokens.md).

Agent-driven token creation from an Admin API token is deliberately **out of scope** for
now — the design and lessons learned are parked in
[references/future-admin-token-flow.md](references/future-admin-token-flow.md).

## Step 3 — Discover stack and region via gcx (prompt on ambiguity)

Use `gcx` to gather the connection inputs the config needs (see
[references/config-patterns.md](references/config-patterns.md) and the token guide):
**region** and numeric **stack ID** via `gcx stacks get <stack-slug>`, plus the hosted
metrics/logs push URLs and instance IDs (`GCLOUD_HOSTED_METRICS_URL/_ID`,
`GCLOUD_HOSTED_LOGS_URL/_ID`).

**If more than one stack (or environment) is available, prompt the user** to pick which
stack and environment should receive the telemetry — never silently choose.

**Fallback when `gcx stacks get` returns 403** (cloud token missing `stacks:read`): the
Grafana *instance* API still has everything via `gcx api /api/datasources`. **Only use
details from datasources whose name matches `grafanacloud-<stack-slug>-*`** — these are
the stack's provisioned Cloud datasources; ignore anything else (e.g. `grafanacloud-usage`,
`grafanacloud-k6`, user-added datasources). From the matching set:
`grafanacloud-<stack-slug>-prom` gives the metrics push URL (its `url` + `/push`) and
`GCLOUD_HOSTED_METRICS_ID` (its `basicAuthUser`); `grafanacloud-<stack-slug>-logs` gives
the logs URL (its `url` + `/loki/api/v1/push`) and `GCLOUD_HOSTED_LOGS_ID`
(`basicAuthUser`); the region is embedded in the Prometheus hostname
(`prometheus-…-<region>.grafana.net`). Fetch individual datasources
(`gcx api /api/datasources/<id>`) to see `basicAuthUser` — the list endpoint omits it.

## Step 4 — Choose execution mode: fan out or sequential (prompt)

Present the per-host plan (host, integrations to apply, pre-instructions that will mutate
services), then **ask the user**: fan out one agent per host to instrument them in
parallel, or work through the hosts sequentially in this session? Fan-out suits many
similar hosts; sequential keeps every action visible in one transcript. Either way each
agent/iteration follows Steps 5–7 per host with the credentials and stack info from
Steps 2–3.

## Step 5 — Per host: install Alloy (self-monitoring baseline)

Shell into the host (`ssh`, `multipass exec`, …). Install Alloy using the provided
credentials and stack information with the official onboarding script and default config —
full procedure in [references/install-linux-vm.md](references/install-linux-vm.md). Fetch
the script fresh from its canonical URL at run time (it pins the current release with
verified checksums; never embed a stale copy):
`https://storage.googleapis.com/cloud-onboarding/alloy/scripts/install-linux.sh`

The default config this installs provides **Alloy self-monitoring only**, plus the
`prometheus.remote_write "metrics_service"` and `loki.write "grafana_cloud_loki"` egress
blocks that every integration snippet forwards to (see
[references/config-patterns.md](references/config-patterns.md) — never duplicate those
egress blocks).

## Step 6 — Per host: install the Linux integration (default)

Every Linux host gets the **Linux Server integration** (`linux-node` slug) — host CPU,
memory, disk, network metrics and journal logs. Pull
`gcx integrations docs linux-node --full` and append its **simple-mode** metrics snippet
and the `linux` logs snippet to `/etc/alloy/config.alloy`, per the procedure in
[references/install-linux-vm.md](references/install-linux-vm.md).

## Step 7 — Per host: instrument each enumerated application

For each application the inventory lists on this host, match it against the integrations
catalog (`gcx integrations list`) and, for each matching slug (e.g. `pgbouncer`):

1. Fetch `gcx integrations docs <slug> --full`.
2. **Follow the "Before you begin" pre-instructions first** — service config changes,
   monitoring users, separate exporters, Alloy runtime changes. These mutate the service:
   confirm each with the user before applying. Skip the docs' portal-UI "Install" steps —
   dashboards/alerts are handled by the future Terraform step.
3. Append the **simple-mode** metrics and logs snippets (the `linux` variant of the logs
   snippet), filling placeholders from the inventory and pre-instruction outputs.
4. Restart Alloy and apply any post-instructions from the docs
   (`sudo systemctl restart alloy.service`, then check status).

**Find the component configuration doc inside each integration's docs.** Every
integration's `--full` page links (from its advanced metrics section) to the reference doc
of the Alloy component it is built on — e.g. `linux-node` →
[`prometheus.exporter.unix`](https://grafana.com/docs/alloy/latest/reference/components/prometheus.exporter.unix/).
The links are relative; resolve them against `https://grafana.com`. When a snippet must be
adapted to the actual inventory (credentials, ports, paths, extra collectors), fetch that
reference doc and configure from it — it is the authoritative spec for the component's
arguments and blocks; never guess component syntax.

Applications with no matching integration fall back to the manual patterns in
[references/config-patterns.md](references/config-patterns.md).

## Step 8 — Summarize and halt

Once all hosts are done (or all fanned-out agents have returned), gather a single summary
for the user: per host — Alloy installed (version), integrations applied, pre-instructions
performed, anything skipped or failed, and whether the Alloy service is healthy. **Halt
here.** Do not continue into dashboards, alerts, or Terraform without a new instruction.

<!-- TODO(research): verification beyond service health — alloy fmt/validate, component
     health via the Alloy UI/API, querying the stack to confirm new series/streams -->

## Future work (TBD)

- **Terraform plan output** — generate a Terraform plan that installs each applied
  integration's dashboards and alerts into the stack (replacing the docs' portal-UI
  "Install" step). Not implemented yet; do not attempt it — just note it in the Step 8
  summary as the next step.
- **Agent-created Alloy tokens** — creating the access policy and token(s) from a
  user-supplied Admin API token, including per-host tokens. Design and lessons learned in
  [references/future-admin-token-flow.md](references/future-admin-token-flow.md).
- **Kubernetes / Docker Compose paths** — reference stubs exist
  ([install-kubernetes.md](references/install-kubernetes.md),
  [install-docker.md](references/install-docker.md)) but the workflow above does not cover
  them yet.

## Best practices

- **Confirm before mutating.** Every prompt above is a hard gate; re-confirm if scope
  changes mid-run.
- **Never emit raw credentials.** Tokens go into config files/secrets, redacted in output.
- **Prefer extending an existing healthy Alloy** over installing a second collector.
- **Idempotent and minimal.** Re-running must not duplicate installs or config blocks.
- **Degrade gracefully.** One unreachable host must not abort the rest of the plan.
