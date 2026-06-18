# Create a Grafana Cloud access-policy token for Grafana Alloy

Goal: a token Alloy can use to ship telemetry, with scopes:
`metrics:write`, `logs:write`, `traces:write`, `profiles:write`, `fleet-management:read`.

> **These are Grafana Cloud *access-policy* scopes, not Grafana-instance RBAC permissions.**
> They are created via the Grafana Cloud portal or the `grafana.com` API.
> **gcx cannot create them** — it can only *consume* the resulting token
> (`gcx login --cloud-token <token>`, or Alloy uses it directly). `gcx api` does not work here
> because it targets the Grafana instance API, not `grafana.com`.

You need two things up front:
- **Region** of your stack (e.g. `prod-us-east-0`). Find it in the portal URL or via
  `gcx stacks get <stack-slug>` (look at the cluster/region).
- **Stack ID** (numeric) — from `gcx stacks get <stack-slug>` or the portal.
- A **management token** with admin scopes (`accesspolicies:read`, `accesspolicies:write`,
  `accesspolicies:delete` as needed) to call the API. Create it once in the portal.

---

## Option A — Grafana Cloud portal (simplest, no API token needed)

1. Go to **https://grafana.com/orgs/&lt;your-org&gt;/access-policies**.
2. Click **Create access policy**.
3. Name it (e.g. `alloy-write`), select the **region** and the **stack** realm.
4. Add scopes: `metrics:write`, `logs:write`, `traces:write`, `profiles:write`,
   `fleet-management:read`.
5. Save, then **Add token**, name it (e.g. `alloy-token`), and **copy the token value now**
   — it is shown only once.

---

## Option B — Grafana Cloud API (`grafana.com`) via `curl`

Set variables (anonymized placeholders):

```bash
REGION="prod-us-east-0"          # your stack's region
STACK_ID="123456"                # numeric stack id
MGMT_TOKEN="glc_..."             # management token with accesspolicies:write
ORG_SLUG="my-org"                # your org slug
```

### 1. Create the access policy

```bash
curl -s -X POST "https://grafana.com/api/v1/accesspolicies?region=${REGION}" \
  -H "Authorization: Bearer ${MGMT_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "alloy-write",
    "displayName": "Alloy write access",
    "realms": [
      { "type": "stack", "identifier": "'"${STACK_ID}"'", "labelPolicies": [] }
    ],
    "scopes": [
      "metrics:write",
      "logs:write",
      "traces:write",
      "profiles:write",
      "fleet-management:read"
    ]
  }'
# -> returns JSON including the access policy "id"
```

Capture the returned policy id:

```bash
POLICY_ID="<id-from-previous-response>"
```

### 2. Create a token under that policy

```bash
curl -s -X POST "https://grafana.com/api/v1/tokens?region=${REGION}" \
  -H "Authorization: Bearer ${MGMT_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "accessPolicyId": "'"${POLICY_ID}"'",
    "name": "alloy-token",
    "displayName": "Alloy token"
  }'
# -> returns JSON with "token": "glc_..."  <-- copy this NOW; shown only once
```

---

## Using the token

The `glc_…` value is the Alloy credential. Typical uses:

- **Alloy config** — use the stack's numeric instance ID as the username and this token as the
  password in each `prometheus.remote_write` / `loki.write` / `otelcol` exporter basic-auth block
  (the portal's "Configuration details" / connection page shows the exact endpoints and usernames
  per signal).
- **gcx (optional, consume only)** — `gcx login <ctx> --server <url> --token <grafana-sa-token> \
  --cloud-token <glc_...>` stores it as the context's cloud token. gcx does **not** create it.

## Notes

- The token secret is returned **once**. If lost, delete the token and create a new one
  (`DELETE https://grafana.com/api/v1/tokens/<tokenId>?region=<region>`).
- Scopes belong to the **access policy**; the token inherits them. To change scopes, update the
  policy (`POST .../accesspolicies/<id>?region=<region>`), not the token.
- `fleet-management:read` lets Alloy pull its remote configuration from Grafana Fleet Management;
  the `*:write` scopes let it push metrics/logs/traces/profiles.
- Verify your region/stack id with `gcx stacks get <stack-slug>` (gcx *is* useful for discovery,
  just not for token creation).
