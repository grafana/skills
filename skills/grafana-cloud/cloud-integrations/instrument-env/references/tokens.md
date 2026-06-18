# Grafana Cloud token for Grafana Alloy

Alloy ships telemetry using a Grafana Cloud **access-policy token**. This file covers the
required scopes, how to create one in the portal, and how the skill prompts for, validates,
and stores it.

## Required scopes

`metrics:write`, `logs:write`, `traces:write`, `profiles:write`, `fleet-management:read`.

> These are Grafana Cloud **access-policy** scopes, not Grafana-instance RBAC permissions.
> They are created via the Grafana Cloud portal (or the `grafana.com` API). **gcx cannot
> create them** — it can only *consume* the resulting token (`gcx login --cloud-token <token>`,
> or Alloy uses it directly). `gcx api` does not work here because it targets the Grafana
> instance API, not `grafana.com`.

`fleet-management:read` lets Alloy pull its remote configuration from Grafana Fleet
Management; the `*:write` scopes let it push metrics/logs/traces/profiles.

## Option A — create the token (Grafana Cloud portal)

1. Go to **https://grafana.com/orgs/&lt;your-org&gt;/access-policies**.
2. Click **Create access policy**.
3. Name it (e.g. `alloy-write`), select the **region** and the **stack** realm.
4. Add the scopes listed above.
5. Save, then **Add token**, name it (e.g. `alloy-token`), and **copy the token value now**
   — it is shown only once.

Scopes belong to the **access policy**; the token inherits them. To change scopes, update the
policy, not the token. If the token secret is lost, delete it and create a new one — it cannot
be recovered.

## The prompt (hard gate, before any install)

The user must supply an existing access-policy token already scoped as above, created manually
in the portal (Option A). Ask them to place it in a mode-600 env file (e.g.
`~/.config/gcx/alloy-token.env` containing `GCLOUD_RW_API_KEY=…`) rather than pasting it into
chat.

If they don't have one, stop and point them at the portal flow above — do not attempt installs
with an unscoped or instance-level token, and do not offer to create one for them.

The user must also be logged in to gcx for stack discovery — `gcx config check` must show a
valid, online context. If not, the prompt must include the login instructions link
<https://github.com/grafana/gcx/blob/74fff38ba3e8f7f9d7529ea7690fdfe905a1713a/docs/reference/login.md>
(`gcx login` with a Cloud Access Policy token; `stacks:read` required baseline). General setup:
<https://github.com/grafana/gcx>.

## Validating the user-supplied token

Token scopes cannot be introspected from the token value alone. Verify functionally: the
install's first remote_write/push is the real test, and a `401`/`403` from the metrics or logs
endpoint means the token is mis-scoped or for the wrong stack — point the user back to the
portal flow rather than retrying.

## Using the token

The `glc_…` value is the Alloy credential: the stack's numeric instance ID is the basic-auth
username and this token is the password in each `prometheus.remote_write` / `loki.write` /
`otelcol` exporter block (the portal's connection page shows the exact endpoints and usernames
per signal). In practice the install script keeps it out of the config file — see secure
storage below.

## Secure storage

- **Linux VM / Multipass**: root-readable env file (e.g. `/root/alloy-install.env`, mode 600)
  holding `GCLOUD_RW_API_KEY=…`; the install script moves it into the systemd override
  `/etc/systemd/system/alloy.service.d/env.conf` (600) — the token never lands in
  `config.alloy`. See [install-linux-vm.md](install-linux-vm.md).

## Redaction rules

- Never echo a `glc_…` value into chat or logs; confirm receipt and reference it by name.
- When showing a config or env file that embeds a token, replace the value with `glc_REDACTED`.
- Token secrets are returned **once** at creation; if lost, delete the token in the portal and
  create a new one.
