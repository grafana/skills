---
name: datasource-provisioning
license: Apache-2.0
description: Generate a copy-paste Grafana data source provisioning file (YAML or Terraform) for any plugin from its standardized settings schema on the plugins CDN. Use when the user wants to provision or configure a data source as code — e.g. "provision infinity", "datasource yaml for clickhouse", "terraform for the github datasource" — even when they only name the plugin and not the word "provisioning".
---

## Workflow

### 1. Ask the starting point: from scratch, or from an existing data source?

**Ask this before anything else** (skip only if the user already made it clear):

- **From scratch** — the user names a plugin type to provision → continue with step 2.
- **From an existing data source** in a running instance → jump to [Convert an existing data source](#convert-an-existing-data-source), then return to step 6.

### 2. Resolve the full plugin id

Provisioning needs the canonical plugin id (`<org>-<name>-datasource`), not the short name a user might say.

- Already canonical (contains `-datasource` or `-app`)? Use as-is: `yesoreyeram-infinity-datasource`.
- Short name only (e.g. `infinity`, `clickhouse`)? Search the catalog API with `filter=<keyword>`:
  ```bash
  curl -s "https://grafana.com/api/plugins?filter=infinity" \
    | jq -r '.items[] | "\(.slug)\t\(.name)"'
  # → yesoreyeram-infinity-datasource    Infinity
  ```
  Multiple matches → show the candidates and ask which one.

The snippets below use Infinity (`yesoreyeram-infinity-datasource`) as the worked example — substitute the id resolved here (and the version from step 3) in every command and output.

### 3. Resolve the latest version

```bash
curl -s "https://grafana.com/api/plugins/yesoreyeram-infinity-datasource" | jq -r '.version'
```

Never hardcode a version — the CDN path is version-pinned and a stale version 404s.

### 4. Fetch the settings schema (primary structured source)

```
https://plugins-cdn.grafana.net/<PLUGIN_ID>/<VERSION>/public/plugins/<PLUGIN_ID>/schema/dsconfig.json
```

```bash
ID=yesoreyeram-infinity-datasource
VER=$(curl -s "https://grafana.com/api/plugins/$ID" | jq -r '.version')
curl -sf "https://plugins-cdn.grafana.net/$ID/$VER/public/plugins/$ID/schema/dsconfig.json"
```

This file conforms to the **dsconfig** schema spec — the source of truth for how to interpret it. Don't re-derive field semantics from memory (`valueType` alone spans `string`, `number`, `boolean`, `array`, `object`, `map`, `any`); consult the spec when a field isn't a plain scalar:

- Prose spec: https://raw.githubusercontent.com/grafana/dsconfig/refs/heads/main/dsconfig/schema.md
- Meta-schema (defines the format of every `dsconfig.json`): https://raw.githubusercontent.com/grafana/dsconfig/refs/heads/main/dsconfig/schema.json

What you need from each field to provision: `key` (the provisioning key), `valueType`, `target` (`root` | `jsonData` | `secureJsonData`), and `validations` (honor `allowedValues` for selectors like `auth_method`). Orientation example (`schemaVersion: "v1"`):

```json
{
  "pluginType": "yesoreyeram-infinity-datasource",
  "fields": [
    {
      "key": "auth_method",
      "valueType": "string",
      "target": "jsonData",
      "validations": [
        {
          "type": "allowedValues",
          "values": [
            "none",
            "basicAuth",
            "apiKey",
            "bearerToken",
            "oauth2",
            "aws",
            "azureBlob"
          ]
        }
      ]
    }
  ]
}
```

Select only the fields relevant to what the user asked for (chosen auth method + connection), not all of them. Each field's `description` tells you which auth method it belongs to.

For ready-made example configs, fetch `v0alpha1.json`:

```
https://plugins-cdn.grafana.net/<PLUGIN_ID>/<VERSION>/public/plugins/<PLUGIN_ID>/schema/v0alpha1.json
```

```bash
ID=yesoreyeram-infinity-datasource
VER=$(curl -s "https://grafana.com/api/plugins/$ID" | jq -r '.version')
curl -sf "https://plugins-cdn.grafana.net/$ID/$VER/public/plugins/$ID/schema/v0alpha1.json"
```

Worked examples live under `settingsExamples.examples`, an object keyed by scenario (e.g. `apiKey`, `oauth2ClientCredentials`). Each entry has a `summary`/`description` (the scenario) and a `value` holding the `jsonData`/`secureJsonData` payload to lift straight into the file:

```bash
# list scenarios, then pull one payload
... | jq -r '.settingsExamples.examples | keys[]'
... | jq '.settingsExamples.examples.apiKey.value'
```

### 5. Fallback when no schema is published

If `schema/dsconfig.json` 404s (older plugins):
- Last resort: the generic structure in [grafana-oss](../grafana-oss/SKILL.md) (§ Data source provisioning) — tell the user the field names are best-effort, not plugin-authoritative.

### 6. Map each field by its `target`

| `target`         | YAML                                                                  | Terraform (`grafana_data_source`)                                                    |
| ---------------- | --------------------------------------------------------------------- | ------------------------------------------------------------------------------------ |
| `root`           | top-level key on the datasource (`url`, `basicAuth`, `basicAuthUser`) | top-level argument (`url`) / inside `json_data_encoded`                              |
| `jsonData`       | under `jsonData:`                                                     | key inside `json_data_encoded = jsonencode({ … })`                                   |
| `secureJsonData` | under `secureJsonData:` as `${ENV_VAR}`                               | key inside `secure_json_data_encoded = jsonencode({ … })` via a `sensitive` variable |

Use each field's `valueType` for the scalar (`string` quoted in YAML, `boolean`→`true`/`false`, `number` bare). Never inline a real secret. Nested objects (`oauth2`, `aws`) and arrays (`allowedHosts`, `scopes`) map directly.

Always set `access` (`root` target) and default it to `proxy` — queries route through the Grafana server (the secure default); only use `direct` (browser → data source) if the user explicitly asks for it. In Terraform the argument is `access_mode`.

### 7. Ask the format, then emit the file

**Now ask: YAML or Terraform?** Same fields, different output file and syntax. Don't assume: "provision X" may mean either; skip the question only if the user already named a format ("terraform for X"). YAML file provisioning is the native, zero-dependency path; Terraform needs the official [`grafana/grafana`](https://registry.terraform.io/providers/grafana/grafana/latest) provider.

| Choice               | Produces                                     |
| -------------------- | -------------------------------------------- |
| **YAML config file** | `provisioning/datasources/<name>.yaml`       |
| **Terraform**        | `<name>.tf` (`grafana_data_source` resource) |

`<name>` is just the file's basename — cosmetic, since both loaders read every file in the directory regardless of name. Default it to the plugin name.

**YAML** → `provisioning/datasources/<name>.yaml`:

```yaml
apiVersion: 1
datasources:
  - name: Infinity # must be unique across the instance — collides even with a different datasource type
    type: yesoreyeram-infinity-datasource # = pluginType from the schema
    access: proxy # always set; default proxy (route queries through the Grafana server)
    uid: infinity-ds # also unique and immutable so dashboards can reference it
    jsonData:
      auth_method: apiKey # value from validations.allowedValues
      apiKeyKey: X-API-Key
      apiKeyType: header
      allowedHosts:
        - https://api.example.com
    secureJsonData:
      apiKeyValue: ${API_KEY} # env var ref, never a literal secret
    editable: false
```

**Terraform** → `<name>.tf`:

```hcl
variable "api_key" {
  type      = string
  sensitive = true
}

resource "grafana_data_source" "infinity" {
  type        = "yesoreyeram-infinity-datasource"
  name        = "Infinity"
  uid         = "infinity-ds"
  access_mode = "proxy" # always set; default proxy (route queries through the Grafana server)

  json_data_encoded = jsonencode({
    auth_method  = "apiKey"
    apiKeyKey    = "X-API-Key"
    apiKeyType   = "header"
    allowedHosts = ["https://api.example.com"]
  })

  secure_json_data_encoded = jsonencode({
    apiKeyValue = var.api_key
  })
}
```

`grafana_data_source` is from the [`grafana/grafana`](https://registry.terraform.io/providers/grafana/grafana/latest/docs/resources/data_source) provider — the authoritative reference for argument names (`access_mode`, `json_data_encoded`, `secure_json_data_encoded`). This file is only the resource; the user supplies the `required_providers` + `provider "grafana"` block and credentials.

### 8. Return the file to the user

Present the complete file in a single code block for the user to copy and paste into their environment — note where it goes:

- **YAML** → `provisioning/datasources/<name>.yaml` (apply on Grafana start or a provisioning reload).
- **Terraform** → their Terraform config, applied with `terraform apply`.

Optionally, tell them how to confirm it worked once applied:

```bash
curl -s https://grafana.example.com/api/datasources/uid/<uid>/health \
  -H "Authorization: Bearer <token>"
# { "status": "OK" }    → working
# { "status": "ERROR" } → URL unreachable or auth misconfigured
```

Or verify in the UI: visit `<https://grafana.example.com>/connections/datasources/edit/<uid>` and click **Test**.

## Convert an existing data source

To codify a data source already configured in a running instance, read its config through the **Grafana MCP server** ([grafana/mcp-grafana](https://github.com/grafana/mcp-grafana)).

**Precondition:** the Grafana MCP server is connected with its **Datasources** toolset enabled (it holds the instance credentials). **If it isn't available, do not support this path** — never ask the user to paste a Grafana token into chat. Fall back to the from-scratch Workflow instead.

1. Find the data source with the MCP tools — `list_datasources` to browse, then `get_datasource` (by `uid` or `name`) for the full config.
2. The result carries every **non-secret** field directly: `type`, `uid`, `url`, `access`, `basicAuth`, `basicAuthUser`, and the full `jsonData` object. Copy them as-is.
3. **Secrets are never returned.** The `secureJsonFields` map lists _which_ secret keys are set (e.g. `{"apiKeyValue": true}`) without their values. Emit an `${ENV_VAR}` placeholder in `secureJsonData` for each key it reports `true`.
4. Cross-check against the schema (step 4) to confirm secret key names and `target` placement, then continue at **step 6** (map) and **step 7** (emit) as normal.

## Related

- [grafana-oss](../grafana-oss/SKILL.md) — generic data source / dashboard provisioning structure and provisioning paths.
