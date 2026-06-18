# Install Alloy on a Linux VM (Multipass / deb / rpm + systemd)

Use the official Grafana Cloud onboarding install script — the same one the Grafana Cloud UI
generates in its "Install Alloy" flow. **Always fetch it from the canonical URL at run time;
never embed a copy** — it pins the current Alloy release with verified sha256 checksums, both
of which change with every release:

```
https://storage.googleapis.com/cloud-onboarding/alloy/scripts/install-linux.sh
```

## Required environment (standalone mode)

| Variable | Meaning |
|---|---|
| `GCLOUD_RW_API_KEY` | Access policy token (see [tokens.md](tokens.md)) |
| `GCLOUD_HOSTED_METRICS_URL` | Hosted metrics push URL (`https://prometheus-…/api/prom/push`) |
| `GCLOUD_HOSTED_METRICS_ID` | Numeric hosted-metrics instance ID (basic-auth username) |
| `GCLOUD_HOSTED_LOGS_URL` | Hosted logs push URL (`https://logs-…/loki/api/v1/push`) |
| `GCLOUD_HOSTED_LOGS_ID` | Numeric hosted-logs instance ID |
| `GCLOUD_SCRAPE_INTERVAL` | Scrape interval for the default pipeline, e.g. `60s` |

The script hard-fails if any of these are unset. Put them in a root-readable env file and
source it rather than passing the token inline on a command line (visible in `ps`):

```bash
set -a; . /root/alloy-install.env; set +a
sh -c "$(curl -fsSL https://storage.googleapis.com/cloud-onboarding/alloy/scripts/install-linux.sh)"
```

For a Multipass VM, `multipass transfer` the env file in, then run the same two lines via
`multipass exec <vm> -- sudo sh -c '…'`.

## What the script does (reviewed behavior to rely on)

1. Supports deb/rpm hosts only (macOS fatals out); auto-detects arch (amd64/arm64/ppc64/s390x)
   and package system. Overridable via `ARCH` / `PACKAGE_SYSTEM`.
2. Downloads the pinned Alloy `.deb`/`.rpm` from GitHub releases and verifies its sha256
   against sums embedded in the script, then installs it (`dpkg -i` / `rpm --reinstall`).
3. Downloads the default config (see [config-patterns.md](config-patterns.md)),
   checksum-verifies it, `sed`-substitutes the `{GCLOUD_*}` placeholders, and installs it to
   `/etc/alloy/config.alloy` (root:root, 644).
4. **The token never lands in the config file.** It is written as
   `Environment=GCLOUD_RW_API_KEY=…` into the systemd override
   `/etc/systemd/system/alloy.service.d/env.conf` (mode 600); the config references it via
   `sys.env("GCLOUD_RW_API_KEY")`.
5. Runs `systemctl daemon-reload`, then `enable` + `start alloy.service`.
   Set `USE_SYSTEMCTL=0` to skip all systemctl calls (e.g. inside a container).

After editing `/etc/alloy/config.alloy`, apply with `sudo systemctl restart alloy.service`
and check `sudo systemctl status alloy.service`.

## Match enumerated services to pre-built integrations (`gcx integrations`)

After the base install, configure the host and its enumerated services from Grafana Cloud's
**pre-built integrations** instead of hand-writing exporter blocks.

> **Note:** the `gcx integrations` subcommand requires a gcx build that includes it. If your
> `gcx` reports the command as unknown, update to a version that ships it.

### 1. Match the inventory against the catalog

```bash
gcx integrations list --json name,slug
```

Output is a JSON array of `{name, slug}` (a hint line precedes it). Match each enumerated
item to a slug:

- **The Linux host itself always maps to `linux-node`** (catalog name "Linux Server").
- Each enumerated application maps to the slug matching its software name, e.g. a pgbouncer
  service → `pgbouncer`, postgres → `postgres`, nginx → `nginx`, redis → `redis`.

Services with no matching slug fall back to the manual patterns in
[config-patterns.md](config-patterns.md).

### 2. Pull the docs for every matched integration

```bash
gcx integrations docs <slug> --full
```

(Without `--full` only the summary is returned.) The full page for each integration
contains, in order:

1. **"Before you begin" — required pre-instructions.** Steps that must be completed *before*
   the Alloy snippets will produce data. They vary per integration and fall into recurring
   categories (surveyed across `pgbouncer`, `docker`, `postgres`, `oracledb`):
   - **Service config changes + restart** — pgbouncer: append
     `ignore_startup_parameters = extra_float_digits` to `pgbouncer.ini` and enable file
     logging (`logfile = …`), then restart; postgres: logs go to stderr by default, logging
     must be configured for the log snippet to have a file to read.
   - **Monitoring credentials in the service** — postgres: create a dedicated low-privilege
     monitoring user (don't use a superuser) and enable the `pg_stat_statements` extension
     for the query-performance dashboard; oracledb: run the provided SQL to create the
     `grafanau` user with specific `GRANT SELECT`s (CDB vs non-CDB variants).
   - **Separate exporter install** — pgbouncer needs the standalone
     [pgbouncer_exporter](https://github.com/prometheus-community/pgbouncer_exporter)
     (metrics on `:9127`); most others (`postgres`, `oracledb`, `docker`) use exporters
     built into Alloy.
   - **Alloy host/runtime changes** — docker: `sudo usermod -a -G docker alloy` for socket
     access, plus running Alloy as root (`systemctl edit --full alloy.service`,
     `User=alloy` → `User=root`) for cAdvisor; oracledb: install the Oracle Instant Client
     and set `ORACLE_HOME` in Alloy's environment file.
   - **Runtime preconditions** — docker: at least one container must be running for the
     connection test to pass.

   Record each pre-instruction in the instrumentation plan as its own confirm-gated action —
   most mutate the *service or host*, not just Alloy. **Read the whole page, not only
   "Before you begin":** some prerequisites appear inline in the snippet sections (oracledb's
   Instant Client requirement is under "Simple mode").
2. **Install steps (portal UI) — ignore.** The docs describe clicking **Install** on the
   integration tile in **Connections** to add the pre-built dashboards and alerts. Skip
   this section entirely: dashboard/alert installation is handled via Terraform in a later
   step of this skill, not through the UI.
3. **Configuration snippets for Grafana Alloy** in two flavors. Use **Simple mode** for this
   flow (single local instance, default ports):
   - the **Integrations snippets** block (metrics — e.g. `prometheus.exporter.unix` for
     `linux-node`), and
   - the **Logs snippets** block, picking the `#### linux` variant where the docs offer
     per-OS variants (postgres ships `darwin`/`linux`/`windows`; use `linux` only).
   Advanced mode is for non-default ports/paths or multi-instance setups only.

   Snippets for database integrations embed connection strings with credential placeholders
   (postgres `data_source_names`, oracledb `connection_string = "oracle://user:password@…"`)
   — substitute the monitoring user created in the pre-instructions, and apply the redaction
   rules from [tokens.md](tokens.md) when echoing any config containing them.
4. **Alloy component reference link (in Advanced mode).** The advanced metrics section names
   the Alloy component the integration is built on and links to its reference docs — e.g.
   `linux-node`: "This integration uses the
   [`prometheus.exporter.unix`](https://grafana.com/docs/alloy/latest/reference/components/prometheus.exporter.unix/)
   component to collect system metrics." The links are relative (`/docs/alloy/latest/…`);
   resolve them against `https://grafana.com`. This reference is the authoritative source
   for every argument and block the component accepts — fetch it whenever a snippet needs
   tuning beyond the published defaults (extra collectors, non-default DSNs/ports, label
   options) instead of guessing component syntax. Read it even when using simple mode if
   the inventory shows a non-default setup.

### 3. Append the snippets to the config

Append the simple-mode metrics and logs snippets for every matched integration to
`/etc/alloy/config.alloy`. They already forward to the base config's
`prometheus.remote_write.metrics_service.receiver` and
`loki.write.grafana_cloud_loki.receiver` — never duplicate those egress blocks
(see [config-patterns.md](config-patterns.md)). Fill any `<your-…>` placeholders (instance
names, log paths) from the inventory, then
`sudo alloy fmt /etc/alloy/config.alloy` to validate and
`sudo systemctl restart alloy.service` to apply.

## Fleet Management mode (out of scope here)

Setting `GCLOUD_FM_URL` (plus `GCLOUD_FM_POLL_FREQUENCY` and `GCLOUD_FM_HOSTED_ID`) switches
the script to a remotely-managed config (`config-fm.alloy`) driven by Grafana Cloud Fleet
Management instead of the local standalone config. This skill's flow is the standalone one;
defer FM-managed installs to the `fleet-management` skill.
