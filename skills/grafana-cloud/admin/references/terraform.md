# Terraform provider for Grafana

Use the official `grafana/grafana` Terraform provider for declarative management of teams, users, folders, dashboards, data sources, etc.

## Minimum viable provider block

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
  auth = var.grafana_service_account_token   # store in tfvars / env, not literal
}
```

## Common resource patterns

### Teams + membership

```hcl
resource "grafana_team" "platform" {
  name  = "Platform Team"
  email = "platform@example.com"
}

resource "grafana_user" "alice" {
  email    = "alice@example.com"
  login    = "alice"
  name     = "Alice"
  password = "changeme"   # ignored when SSO is configured
}

resource "grafana_team_member" "platform_alice" {
  team_id = grafana_team.platform.id
  user_id = grafana_user.alice.id
}
```

### Folders + dashboards

```hcl
resource "grafana_folder" "platform_dashboards" {
  title = "Platform Dashboards"
}

resource "grafana_dashboard" "overview" {
  folder      = grafana_folder.platform_dashboards.uid
  config_json = file("dashboards/overview.json")
}
```

## Validating the apply

After `terraform apply`:

1. `terraform plan` — should be clean (no drift)
2. Confirm in the Grafana UI:
   - Teams → "Platform Team" present with the expected members
   - Dashboards → folder + dashboard visible
3. If a resource shows as drift on the next plan but you haven't touched it: someone is modifying the same resource in the UI. Either reclaim it via Terraform (move all changes to code) or exclude it (use the `ignore_changes` lifecycle block).

## Common failure modes

| Symptom | Likely cause |
|---|---|
| `401 Unauthorized` on apply | Service account token expired or wrong stack URL |
| `409 Conflict` on resource create | Resource already exists in Grafana; import it first (`terraform import`) |
| Drift on every plan despite no UI changes | Provisioning files on disk modifying the same resource; pick one source of truth |
