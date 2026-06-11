# SSO / Auth Configuration

Provider-specific `grafana.ini` blocks. Drop one of these into your config, restart Grafana, then validate the login flow per [§ Verifying SSO](#verifying-sso) below.

## Generic OAuth (e.g. Okta)

```ini
[auth.generic_oauth]
enabled = true
name = Okta
allow_sign_up = true
client_id = your_client_id
client_secret = your_client_secret
scopes = openid profile email groups
auth_url = https://your-org.okta.com/oauth2/v1/authorize
token_url = https://your-org.okta.com/oauth2/v1/token
api_url = https://your-org.okta.com/oauth2/v1/userinfo
role_attribute_path = contains(groups[*], 'grafana-admins') && 'Admin' || 'Viewer'
groups_attribute_path = groups
```

## SAML (Enterprise / Cloud)

```ini
[auth.saml]
enabled = true
certificate_path = /etc/grafana/saml/grafana.crt
private_key_path = /etc/grafana/saml/grafana.key
idp_metadata_path = /etc/grafana/saml/idp-metadata.xml
max_issue_delay = 90s
metadata_valid_duration = 48h
assertion_attribute_login = mail
assertion_attribute_email = mail
assertion_attribute_name = displayName
assertion_attribute_role = role
role_values_admin = grafana-admins
role_values_editor = grafana-editors
```

## GitHub OAuth

```ini
[auth.github]
enabled = true
allow_sign_up = true
client_id = your_github_client_id
client_secret = your_github_client_secret
scopes = user:email,read:org
auth_url = https://github.com/login/oauth/authorize
token_url = https://github.com/login/oauth/access_token
api_url = https://api.github.com/user
allowed_organizations = ["your-org"]
team_ids = [123456]
role_attribute_path = "Admin"
```

## Verifying SSO

After restart, before announcing the change to users:

1. **Open the login page in an incognito window.** The new provider button should be visible.
2. **Click the provider button.** You should be redirected to the IdP, then back to Grafana logged in.
3. **Check the user's role.** Hit `https://yourstack.grafana.net/api/users/lookup?loginOrEmail=<your-email>` — the response's `role` field should match what your `role_attribute_path` / `role_values_*` mapping should have produced.
4. **If the role is wrong**, look at the IdP's actual claims:
   ```bash
   # Grafana logs the parsed claims on debug-level auth login
   journalctl -u grafana-server | grep -i "OAuth\|SAML" | tail -50
   ```
   The fix is almost always a mismatch between the claim path and the IdP's actual response shape.

5. **If login itself fails**, check `auth_url` / `token_url` / `api_url` for typos and confirm the IdP's allowed redirect URIs include `https://yourstack.grafana.net/login/<provider>`.

## Common failure modes

| Symptom | Likely cause |
|---|---|
| 500 after redirect from IdP | Wrong `token_url` or expired `client_secret` |
| User logs in but no role assigned | `role_attribute_path` expression doesn't match the IdP's claim shape |
| `redirect_uri_mismatch` from IdP | The IdP's app config is missing `https://yourstack.grafana.net/login/<provider>` as an allowed redirect URI |
| SAML "invalid signature" | Stale `idp_metadata.xml` — re-fetch from the IdP |
