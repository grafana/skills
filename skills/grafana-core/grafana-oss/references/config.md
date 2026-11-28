# grafana.ini configuration

Reference for `grafana.ini` server-side settings.

## Contents

- [Server + database](#server--database)
- [Alerting](#alerting)
- [SMTP](#smtp)
- [Auth (OAuth example)](#auth-oauth-example)
- [Security](#security)
- [Feature toggles](#feature-toggles)

## Server + database

```ini
[server]
http_port = 3000
domain = grafana.example.com
root_url = https://grafana.example.com/

[database]
type = postgres
host = postgres:5432
name = grafana
user = grafana
password = secret
```

After changing these, restart Grafana and verify:
- `curl http://localhost:3000/api/health` returns `{"database": "ok", ...}`
- `curl http://localhost:3000/api/admin/settings | jq '.database'` shows the new config

## Alerting

```ini
[unified_alerting]
enabled = true
```

Never set `[alerting] enabled = true`: that key belongs to the legacy alerting removed in Grafana 11, and Grafana refuses to start while it is `true`.

## SMTP

```ini
[smtp]
enabled = true
host = smtp.gmail.com:587
user = alerts@example.com
password = yourpassword
from_address = alerts@example.com
```

Verify by sending a test email via the Alerting → Contact points UI.

## Auth (OAuth example)

```ini
[auth.generic_oauth]
enabled = true
name = Okta
client_id = your_client_id
client_secret = your_secret
auth_url = https://your-org.okta.com/oauth2/v1/authorize
token_url = https://your-org.okta.com/oauth2/v1/token
api_url = https://your-org.okta.com/oauth2/v1/userinfo
scopes = openid profile email groups
```

For SAML and GitHub OAuth, see the [grafana-cloud/admin skill](../../../grafana-cloud/admin/references/sso.md). The configs are the same in OSS.

## Security

```ini
[security]
admin_user = admin
admin_password = secret
allow_embedding = true       # required for embedding dashboards in iframes
```

`admin_password` is only consulted on first startup. To change it later, run `grafana cli admin reset-admin-password --password-from-stdin`, which reads the new password from stdin instead of the command line. Grafana 13 removed the `grafana-cli` binary (deb and rpm packages keep it only as a deprecated wrapper): use `grafana cli`.

## Feature toggles

```ini
[feature_toggles]
enable = publicDashboards
```

Multiple toggles are space-separated:
```ini
enable = publicDashboards correlations grafanaApiServer
```

## Common problems

- **`grafana.ini` changes need a restart** — config is read at startup, not live-reloaded
- **`root_url` matters for OAuth callbacks** — if you set `domain` but not `root_url`, OAuth redirect URIs may not match
- **Sections are global** — `[server]`, `[database]`, etc. apply at the process level, not per-org
