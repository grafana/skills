# Grafana Cloud token acquisition flow

Operational companion to
[grafana-alloy-token-guide.md](grafana-alloy-token-guide.md) (which documents the scopes and
the portal creation steps). This file covers how the skill **prompts for, validates, and
stores** the token.

## Required scopes (recap)

`metrics:write`, `logs:write`, `traces:write`, `profiles:write`, `fleet-management:read` —
access-policy scopes on `grafana.com`, not Grafana-instance RBAC. `gcx` cannot create these
tokens; it can only consume them.

## The prompt (hard gate, before any install)

The user must supply an existing access-policy token already scoped as above, created
manually in the Grafana Cloud portal (token guide, Option A). Ask them to place it in a
mode-600 env file (e.g. `~/.config/gcx/alloy-token.env` containing
`GCLOUD_RW_API_KEY=…`) rather than pasting it into chat.

If they don't have one, stop and point them at the portal flow (token guide, Option A) —
do not attempt installs with an unscoped or instance-level token, and do not offer to
create one: agent-driven token creation is parked in
[future-admin-token-flow.md](future-admin-token-flow.md).

The user must also be logged in to gcx for stack discovery — `gcx config check` must show
a valid, online context. If not, the prompt must include the login instructions link
<https://github.com/grafana/gcx/blob/74fff38ba3e8f7f9d7529ea7690fdfe905a1713a/docs/reference/login.md>
(`gcx login` with a Cloud Access Policy token; `stacks:read` required baseline). General
setup: <https://github.com/grafana/gcx>.

## Validating the user-supplied token

Token scopes cannot be introspected from the token value alone. Verify functionally: the
install's first remote_write/push is the real test, and a `401`/`403` from the metrics or
logs endpoint means the token is mis-scoped or for the wrong stack — point the user back to
the token guide rather than retrying.

## Secure storage per environment

- **Linux VM / Multipass**: root-readable env file (e.g. `/root/alloy-install.env`, mode
  600) holding `GCLOUD_RW_API_KEY=…`; the install script moves it into the systemd override
  `/etc/systemd/system/alloy.service.d/env.conf` (600) — the token never lands in
  `config.alloy`. See [install-linux-vm.md](install-linux-vm.md).
- **Kubernetes**: a `Secret`, referenced via env in the Alloy Helm values.
- **Docker / Compose**: `env_file` or Compose secrets — never inline in `compose.yaml`.

## Redaction rules

- Never echo a `glc_…` value into chat or logs; confirm receipt and reference it by name.
- When showing a config or env file that embeds a token, replace the value with
  `glc_REDACTED`.
- Token secrets are returned **once** at creation; if lost, the token must be deleted in
  the portal and a new one created.
