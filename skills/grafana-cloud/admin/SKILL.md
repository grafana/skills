---
name: admin
license: Apache-2.0
description: Manage Grafana Cloud accounts — organizations, stacks, RBAC roles and assignments, SSO/SAML/OAuth/GitHub auth, service accounts for CI/CD, user invites, team membership, and API-driven provisioning. Creates stacks via the Cloud API, mints service-account tokens, applies role assignments, configures SSO providers, and provisions teams/folders/dashboards via Terraform. Use when managing Grafana Cloud access, configuring SSO/SAML/OAuth, setting up service accounts for Terraform/CI/CD, assigning RBAC roles, inviting users, managing multiple stacks or organizations, provisioning cloud resources via API or Terraform, or auditing admin actions — even when the user says "set up SSO", "create a stack", "make a service account", or "onboard a team" without explicitly saying "admin".
---

# Grafana Cloud Admin

> **Docs**: https://grafana.com/docs/grafana-cloud/account-management.md

## Common Workflows

### Setting up a new stack

```bash
# 1. Create the stack via Cloud API
curl -X POST https://grafana.com/api/instances \
  -H "Authorization: Bearer <grafana-com-api-key>" \
  -H "Content-Type: application/json" \
  -d '{"name": "my-new-stack", "slug": "my-new-stack", "region": "us-east-0", "plan": "grafana-cloud-free"}'

# 2. Verify the stack is reachable (poll until 200)
until curl -fs https://my-new-stack.grafana.net/api/health > /dev/null; do sleep 2; done

# 3. Mint an admin service-account token (see § Service Accounts below)

# 4. Test the token
curl https://my-new-stack.grafana.net/api/org -H "Authorization: Bearer <token>"
# Returns 200 + org JSON → token works
```

### Onboarding a team

1. Invite users via `POST /api/org/invites` (one curl per user — see [references/api-reference.md § Stack API](references/api-reference.md#stack-api--user--team--org-management))
2. Create the team via `POST /api/teams`
3. Add each user via `POST /api/teams/{teamId}/members`
4. Assign an RBAC role to the team (see [§ RBAC](#rbac) below)
5. Verify: `GET /api/teams/{teamId}/members` returns the expected user list

### Configuring SSO (Okta / SAML / GitHub)

1. Pick the provider config from [references/sso.md](references/sso.md) and drop into `grafana.ini`
2. Restart Grafana
3. **Always validate in an incognito window before announcing**: see [references/sso.md § Verifying SSO](references/sso.md#verifying-sso) for the 5-step verification + role-mapping debug pattern

### Deleting a stack (destructive)

```bash
# 1. Delete via Cloud API
curl -X DELETE https://grafana.com/api/instances/{id} \
  -H "Authorization: Bearer <grafana-com-api-key>"

# 2. Verify the stack is gone (must return 404)
curl https://grafana.com/api/instances/{id} \
  -H "Authorization: Bearer <grafana-com-api-key>"
```

If the GET still returns 200 after a few seconds, the delete didn't apply — re-check the stack ID and Cloud API key.

## Organization and Stack Structure

```
Grafana Cloud Account
└── Organization (billing unit)
    ├── Stack 1 (prod)   → dedicated Grafana, Prometheus, Loki, Tempo URLs
    ├── Stack 2 (staging)
    └── Stack 3 (dev)
```

- **Organization**: top-level account with billing, users, API keys, stacks
- **Stack**: dedicated Grafana + LGTM instance with its own URLs and credentials

## User Roles

| Role | Scope | Permissions |
|------|-------|-------------|
| **Org Admin** | Organization | Manage stacks, users, billing, API keys |
| **Admin** | Stack | Data sources, plugins, users, provisioning |
| **Editor** | Stack | Create/edit dashboards, alerts |
| **Viewer** | Stack | Read-only dashboards |

## RBAC

Define a custom role + assignment in provisioning YAML:

```yaml
# provisioning/access-control/roles.yaml
apiVersion: 1
roles:
  - name: TeamDashboardEditor
    description: Edit dashboards within team folder
    permissions:
      - action: dashboards:read
        scope: folders:UID:team-folder
      - action: dashboards:write
        scope: folders:UID:team-folder
      - action: dashboards:create
        scope: folders:UID:team-folder
```

```yaml
# provisioning/access-control/assignments.yaml
apiVersion: 1
roleAssignments:
  - roleName: TeamDashboardEditor
    users:
      - alice@example.com
      - bob@example.com
    teams:
      - platform-team
```

After committing the YAML and restarting Grafana, verify the role applied: `GET /api/access-control/roles | jq '.[] | select(.name=="TeamDashboardEditor")'`.

## Service Accounts

Service accounts are the recommended way for programmatic access (CI/CD, Terraform, agents).

```bash
# 1. Create the service account
curl -X POST https://yourstack.grafana.net/api/serviceaccounts \
  -H "Authorization: Bearer <admin-token>" \
  -H "Content-Type: application/json" \
  -d '{"name": "terraform-provisioner", "role": "Admin", "isDisabled": false}'

# 2. Mint a token for it
curl -X POST https://yourstack.grafana.net/api/serviceaccounts/{id}/tokens \
  -H "Authorization: Bearer <admin-token>" \
  -H "Content-Type: application/json" \
  -d '{"name": "ci-token", "secondsToLive": 0}'

# 3. Verify the token works (test on a harmless endpoint)
curl https://yourstack.grafana.net/api/org \
  -H "Authorization: Bearer <new-token>"
# 200 + org JSON → token works. Anything else → re-check role assignment in step 1.
```

Provisioning equivalent (YAML, declarative):

```yaml
# provisioning/access-control/service_accounts.yaml
apiVersion: 1
serviceAccounts:
  - name: alloy-writer
    orgId: 1
    role: Editor
    tokens:
      - name: alloy-token
```

## References

- [`references/sso.md`](references/sso.md) — OAuth / SAML / GitHub OAuth config + the 5-step SSO verification pattern + common failure modes
- [`references/terraform.md`](references/terraform.md) — Terraform provider config + common resource patterns (teams, users, folders, dashboards) + drift troubleshooting
- [`references/api-reference.md`](references/api-reference.md) — full Cloud API + Stack API endpoint reference + audit-log queries
