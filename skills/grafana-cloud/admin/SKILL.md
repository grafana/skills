---
name: admin
license: Apache-2.0
description: >
  Grafana Cloud account management — organizations, stacks, RBAC, SSO/SAML/OAuth, service accounts,
  API keys, team management, billing, and cloud-level provisioning. Use when managing Grafana Cloud
  access, configuring SSO, setting up service accounts for CI/CD, assigning roles, managing multiple
  stacks or organizations, or provisioning cloud resources via API.
---

# Grafana Cloud Admin

> **Docs**: https://grafana.com/docs/grafana-cloud/account-management/

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

## RBAC (Cloud / Enterprise)

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

## Service Accounts

Service accounts are the recommended way for programmatic access (CI/CD, Terraform, agents):

```bash
# Create service account via API
curl -X POST https://yourstack.grafana.net/api/serviceaccounts \
  -H "Authorization: Bearer <admin-token>" \
  -H "Content-Type: application/json" \
  -d '{"name": "terraform-provisioner", "role": "Admin", "isDisabled": false}'

# Create token for service account
curl -X POST https://yourstack.grafana.net/api/serviceaccounts/{id}/tokens \
  -H "Authorization: Bearer <admin-token>" \
  -H "Content-Type: application/json" \
  -d '{"name": "ci-token", "secondsToLive": 0}'
```

Provisioning via YAML:
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

## SSO / Auth Configuration

### OAuth (grafana.ini)

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

### SAML (Enterprise)

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

### GitHub OAuth

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

## Cloud API for Stack Management

```bash
# List stacks
curl https://grafana.com/api/instances \
  -H "Authorization: Bearer <grafana-com-api-key>"

# Create stack
curl -X POST https://grafana.com/api/instances \
  -H "Authorization: Bearer <grafana-com-api-key>" \
  -H "Content-Type: application/json" \
  -d '{"name": "my-new-stack", "slug": "my-new-stack", "region": "us-east-0", "plan": "grafana-cloud-free"}'

# Delete stack
curl -X DELETE https://grafana.com/api/instances/{id} \
  -H "Authorization: Bearer <grafana-com-api-key>"
```

## Terraform Provider

```hcl
terraform {
  required_providers {
    grafana = {
      source  = "grafana/grafana"
      version = "~> 2.0"
    }
  }
}

provider "grafana" {
  url  = "https://yourstack.grafana.net"
  auth = var.grafana_service_account_token
}

resource "grafana_team" "platform" {
  name  = "Platform Team"
  email = "platform@example.com"
}

resource "grafana_user" "alice" {
  email    = "alice@example.com"
  login    = "alice"
  name     = "Alice"
  password = "changeme"
}

resource "grafana_team_member" "platform_alice" {
  team_id = grafana_team.platform.id
  user_id = grafana_user.alice.id
}

resource "grafana_folder" "platform_dashboards" {
  title = "Platform Dashboards"
}

resource "grafana_dashboard" "overview" {
  folder      = grafana_folder.platform_dashboards.uid
  config_json = file("dashboards/overview.json")
}
```

## Audit Logs

```bash
# Query audit logs (Enterprise/Cloud)
GET /api/admin/auditlogs?query=login&from=1706745600&to=1706832000&limit=50
```

## Key Admin API Endpoints

```bash
# List org users
GET /api/org/users

# Invite user to org
POST /api/org/invites
{ "loginOrEmail": "user@example.com", "role": "Editor", "sendEmail": true }

# Update user org role
PATCH /api/org/users/{userId}
{ "role": "Admin" }

# List teams
GET /api/teams/search?name=platform

# Create team
POST /api/teams
{ "name": "Platform Team", "email": "platform@example.com" }

# Add user to team
POST /api/teams/{teamId}/members
{ "userId": 2 }
```
