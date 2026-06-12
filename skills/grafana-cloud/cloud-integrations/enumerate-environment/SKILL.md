---
name: enumerate-environment
license: Apache-2.0
description: >
  Enumerate the container, VM, and cluster environments running on a host and produce a single
  inventory of all running software, grouped by category and namespace. Auto-detects Docker /
  Docker Compose, Multipass VMs, and Kubernetes (kubectl). All operations are strictly read-only.
  Use when the user asks to enumerate or inventory a local environment, list what's running, see
  what software/services are deployed across docker-compose / multipass / kubernetes, audit a host,
  check whether Alloy is already installed, or group running workloads by category and namespace.
  Triggers on phrases like "enumerate environment", "what's running", "list running software",
  "inventory the host", "what's deployed", "multipass list", "kubectl get pods", "docker compose ls".
---

# Enumerate Environment

Build a single inventory of everything running on a host across three environment types, grouped by
**namespace** and **category**. The host may have any combination of:

- **Kubernetes** — workloads grouped by namespace (`kubectl`), often multiple contexts (e.g. k3d/kind).
- **Multipass** — Ubuntu VMs; each VM's name acts as a namespace, its services are the software.
- **Docker / Docker Compose** — containers grouped by Compose project (project = namespace).

**Environments nest — recurse into them.** A Multipass VM may run its own Docker/Compose stack, and
a container may itself run Docker/Compose. Whenever an inner container runtime is detected, descend
into it: enumerate the inner containers as a **nested namespace** (`<outer> › <inner-project>`),
categorize them, **and check each inner container for Alloy/Grafana-Agent presence**. Recurse as
deep as inner runtimes are found (typically 1–2 levels; guard against cycles and cap depth).

**This skill is strictly read-only.** Never start, stop, restart, create, delete, `apply`, `exec`
into a mutating shell, or otherwise modify any workload, VM, container, or cluster. Only listing,
`get`, `inspect`, and read-only `exec`/`systemctl is-active` style probes are allowed.

## Step 1 — Detect available environments, then confirm scope

First detect which tools exist and what they can see. **Do not assume which context, VM, or project
to enumerate** — discover the full list, present it, and get firm confirmation before enumerating.

```bash
# Which environment tools are installed?
command -v kubectl multipass docker 2>/dev/null

# Kubernetes: list ALL contexts — do NOT default to the current one
kubectl config get-contexts

# Multipass: list all instances and their state
multipass list

# Docker: standalone containers + Compose projects
docker ps
docker compose ls
```

**Confirmation gate (required).** Show the user the discovered contexts / VMs / Compose projects and
ask which to enumerate. This is a hard gate — proceed to Step 2 only against the contexts, VMs, and
projects the user explicitly confirms. Enumerating every kubectl context by default can be slow and
may touch clusters the user did not intend, so always confirm first.

If a tool is missing or a target is unreachable, note it and continue with the rest — never fail the
whole run because one environment is unavailable. **Do not carry unreachable contexts into the
report.** Only reachable, enumerated contexts appear in the output (see Step 4); a context whose API
is down/refused is simply omitted, not listed by name.

### Choose execution mode: parallel or sequential

Once the scope is confirmed, **count the units of work** before enumerating — this is cheap and
tells you whether parallelism is worth it:

```bash
# Namespace count per confirmed, reachable context (one light call each) — a size signal only;
# the parallel unit of work is the context, not the namespace.
kubectl --context <ctx> --request-timeout=8s get ns --no-headers | wc -l
# VM count and docker presence are already known from Step 1 (multipass list / docker ps)
```

**Then prompt the user** with the tally and let them choose, e.g.:

> *Found **M** Kubernetes contexts (**N** namespaces total), **K** Multipass VMs, and Docker. This can
> be enumerated sequentially (slower, one context at a time) or in parallel by spawning one sub-agent
> per Kubernetes context, one for Docker, and one for Multipass. **Run in parallel?***

- Default to **sequential** for small scopes (e.g. a single context plus a handful of VMs) — the
  orchestration overhead isn't worth it. Recommend **parallel** when several contexts are confirmed
  (or one very large context alongside many VMs).
- **If the user chooses parallel**, spawn sub-agents (a single message with multiple agent calls so
  they run concurrently):
  - **one sub-agent per Kubernetes context** (scoped to `--context <ctx>`; it enumerates all that
    context's namespaces and runs the standalone Alloy coverage pass for its own cluster),
  - **one sub-agent for Docker** (all containers + Compose projects on the host),
  - **one sub-agent for Multipass** (all confirmed VMs; it may further batch per VM).
  Each sub-agent runs **only** the read-only Step 2–3 procedure for its slice and **returns a compact
  structured inventory** (namespace, category, software, image/version, Alloy coverage) — not raw
  command dumps. The orchestrator merges these into the single Step 4 report.
- All sub-agents inherit the same rules: **read-only**, **redact credentials**, summarize don't dump,
  recurse into nested runtimes, and degrade gracefully on unreachable targets.

## Step 2 — Enumerate each confirmed environment

The "namespace" concept maps differently per environment:

| Environment | Namespace = | Software source |
|---|---|---|
| Kubernetes | k8s namespace | pod / container images |
| Multipass | VM name | running systemd services + listening ports |
| Docker | Compose project (or `host` for standalone) | container images |

**Efficiency defaults (do this to save time and tokens):**
- **One round-trip per target.** Each `multipass exec` / `kubectl` / `docker exec` call has real
  latency — batch everything you need from a VM into a **single** `multipass exec <vm> -- bash -c`
  (see below), not one call per fact.
- **Filter noise at the source**, not after. Drop OS/system services with `grep -vE` inside the
  remote command so the noise never crosses the wire into your context.
- **Fast-fail unreachable targets** with `--request-timeout=8s` (kubectl) so dead contexts return in
  seconds instead of hanging on the default ~30s+ timeout.
- **Summarize, don't dump.** For Alloy configs, return the component inventory + egress endpoints
  (a dozen lines) rather than the whole file.

### Kubernetes

Run against each **confirmed context** (`--context <ctx>`). Two quick calls — status (accurate,
includes `CrashLoopBackOff`/restarts) and images for categorization:

```bash
# 1) Status table — compact, fast-fail on dead contexts. (Skip -o wide unless you need node/IP.)
kubectl --context <ctx> --request-timeout=8s get pods -A

# 2) Images per pod for categorization (one pass)
kubectl --context <ctx> --request-timeout=8s get pods -A --no-headers \
  -o custom-columns='NS:.metadata.namespace,POD:.metadata.name,IMAGES:.spec.containers[*].image'
```

Use call (1) to know which pods are actually `Running`/`Completed` — derive it with `awk`,
no extra cluster hit. This is an **internal** scoping check (it tells you what to enumerate
and lets you skip dead workloads); workload health is **not** reported in the output — see
Step 4, which omits any status column or health callout.

```bash
kubectl --context <ctx> --request-timeout=8s get pods -A --no-headers \
  | awk '$4!="Running" && $4!="Completed" {print $1"/"$2"  "$4"  ready="$3"  restarts="$5}'
```

### Multipass

For each **confirmed, `Running`** VM, gather everything in **one** batched call — services (OS noise
filtered at the source), listening ports, the Alloy presence check, and nested-runtime detection:

```bash
multipass exec <vm> -- bash -c '
  echo "### services"
  systemctl list-units --type=service --state=running --no-legend --plain | awk "{print \$1}" \
    | grep -vE "^(systemd-|getty@|serial-getty@|user@|dbus|polkit|cron|ssh|rsyslog|ModemManager|multipathd|udisks2|unattended-upgrades|snapd|fwupd|networkd-dispatcher|packagekit|accounts-daemon)"
  echo "### ports";  (ss -tlnp 2>/dev/null || ss -tln) | awk "NR>1{print \$4}"
  echo "### alloy";  systemctl is-active alloy grafana-agent 2>/dev/null; command -v alloy grafana-agent 2>/dev/null
  echo "### docker"; command -v docker >/dev/null && docker ps --format "{{.Names}}\t{{.Image}}\t{{.Label \"com.docker.compose.project\"}}" || echo none
'
```

The `### docker` section doubles as recursion input: if it lists containers, descend into them (next
subsection). Map listening ports to services via the `### services` list rather than running
privileged `ss -tlnp` (process names need root).

### Recursion — nested container runtimes

When an inner Docker/Compose runtime is found inside a VM (or inside a container), enumerate the
inner containers as a nested namespace and run the Alloy check on **each** of them. The outer command
prefix differs by host (`multipass exec <vm> --` for a VM, `docker exec <ctr>` for a container), but
the inner commands are identical:

```bash
# Inner containers + their Compose project (the nested namespace). For a VM:
multipass exec <vm> -- sh -c \
  'docker ps --format "{{.Names}}\t{{.Image}}\t{{.Label \"com.docker.compose.project\"}}"'

# Nested namespace = "<vm> › <compose-project>"; inner containers with no project label go under
# "<vm> › host". Categorize each inner image with the Step 3 taxonomy.
```

Detect Alloy per inner container **primarily from its name/image** — many minimal/distroless images
(e.g. mimir, loki) have **no shell**, so `docker exec … sh` will fail. Treat the exec probe as
best-effort and fall back to name/image matching:

```bash
# Reliable: name/image already tells you (no exec needed)
#   ubuntu_alloy_1  grafana/alloy:v1.x      → Alloy present
# Best-effort confirmation (ignore "executable file not found"/"no such file" — distroless):
multipass exec <vm> -- sh -c 'docker exec <inner-ctr> sh -c "command -v alloy grafana-agent" 2>/dev/null' || true
```

If the inner container itself runs Docker/Compose, recurse again (cap depth, skip already-seen IDs).

### Docker / Docker Compose

```bash
# Running containers: name, image, status
docker ps --format '{{.Names}}\t{{.Image}}\t{{.Status}}'

# Compose projects (each project is a namespace)
docker compose ls

# Containers belonging to a specific Compose project
docker ps --filter "label=com.docker.compose.project=<project>" \
  --format '{{.Names}}\t{{.Image}}\t{{.Status}}'
```

Group containers by their Compose project label; containers with no project go under `host`. If any
container itself runs Docker/Compose (e.g. a CI-in-Docker or dind image), recurse into it using the
same procedure as the **Recursion** subsection above.

## Step 3 — Categorize and check for an existing collector

Map each piece of software to a category by matching keywords in its image or service name:

| Category | Match keywords |
|---|---|
| **Databases** | mysql, mariadb, postgres / postgresql, redis, memcached, mongodb |
| **Observability / Telemetry** | grafana, alloy, grafana-agent, mimir, loki, tempo, pyroscope, prometheus, kube-state-metrics, metrics-server, node_exporter, otel / opentelemetry |
| **Web / App services** | nginx, traefik, `*-api`, node, http servers, sample apps |
| **Messaging / Streaming** | kafka, rabbitmq, nats |
| **Storage** | minio, s3, ceph |
| **Platform / Infra** | coredns, kube-proxy, k3s / k3d, `helm-install-*` bootstrap jobs, registry, local-path-provisioner, svclb |
| **System / OS** *(filtered out by default)* | systemd-*, getty, dbus, polkit, cron, sshd, ModemManager, multipathd, udisks2, unattended-upgrades, snapd |

Exclude the **System / OS** row from the inventory by default (mention that it was filtered). Bucket
anything unmatched under **Other** and surface its raw name so nothing is silently dropped.

### Alloy / collector presence check (read-only)

For local workflows, determine whether a Grafana collector (**Alloy** or the legacy **Grafana Agent**)
is *already installed* on each VM / container — so the inventory reflects existing telemetry coverage.
These are detection-only probes; **never install, start, or modify anything**.

```bash
# Multipass VM — is a collector active or on PATH?
multipass exec <vm> -- sh -c 'systemctl is-active alloy grafana-agent 2>/dev/null; command -v alloy grafana-agent 2>/dev/null'

# Docker — container or image named alloy / grafana-agent?
docker ps --filter "name=alloy" --filter "name=grafana-agent" --format '{{.Names}}\t{{.Image}}'
docker exec <container> sh -c 'command -v alloy grafana-agent 2>/dev/null'   # read-only check
```

In Kubernetes, the collector usually shows up directly in the pod/image listing (`alloy`,
`grafana-agent`) — no extra probe is needed to detect its **presence**. Determining **coverage**
(which pods/services it actually instruments) requires connecting to the instance and correlating its
config — see *Kubernetes — standalone Alloy coverage* at the end of this step.

**For nested containers** (found via recursion), prefer name/image matching over `docker exec`,
since distroless/minimal images have no shell. A failed exec probe (`executable file not found`,
`no such file`) is **not** a "no" — fall back to the name/image signal.

Record an **Alloy installed: yes/no** signal **per namespace and per nested namespace** (e.g. a VM
may have no host-level Alloy yet run an Alloy container inside its Docker stack, or vice-versa —
report both levels).

**Presence is not coverage — lead with the coverage reality, not a bare "YES".** Once the coverage
pass (below) has run, the "Alloy installed" summary line must front-load *what it actually covers*: a
collector that is present but scrapes little or nothing should read like *"present but effectively
uncovering — only self-metrics, no host/app/log coverage"* **at the start of the line**, not a "YES"
that buries the gap at the end. Put the reassuring context (e.g. "an LGTM stack is also present") last.

### Capture the Alloy config (read-only, credentials redacted)

When Alloy/Grafana-Agent **is** present, also capture a copy of its configuration to inform future
instrumentation (what's already scraped, which `remote_write` endpoints, which exporters). This is
read-only — only ever `cat`/`get` the file, never edit it. **Always pipe the config through a
redaction filter before saving or displaying it** — never emit raw credentials.

Locate the config, then redact:

```bash
# Multipass VM (systemd Alloy): the path comes from $CONFIG_FILE in /etc/default/alloy
#   (default /etc/alloy/config.alloy). Grafana Agent: /etc/grafana-agent.yaml or /etc/agent/agent.yaml
multipass exec <vm> -- sh -c 'sudo cat "${CONFIG_FILE:-/etc/alloy/config.alloy}" 2>/dev/null || cat "${CONFIG_FILE:-/etc/alloy/config.alloy}"' | <REDACT>

# Container Alloy: find the config flag, then read that path inside the container
docker inspect <ctr> --format '{{join .Args " "}}'        # look for --config.file / config.alloy
docker exec <ctr> sh -c 'cat /etc/alloy/config.alloy' 2>/dev/null | <REDACT>   # if a shell exists

# Kubernetes Alloy: the ConfigMap is a fallback — prefer the *running* config read straight from the
#   pod (see "Kubernetes — standalone Alloy coverage" below). ConfigMap config is in YAML/River:
kubectl --context <ctx> -n <ns> get configmap <alloy-cm> -o jsonpath='{.data}' | <REDACT-YAML>
```

`<REDACT>` for Alloy/River syntax (`key = "value"`) — masks the value of any credential-like key
while **preserving endpoint URLs** (which are useful, not secret):

```bash
sed -E 's/((password|passwd|secret|token|api_?key|access_?key|secret_?key|bearer_token|authorization|credential|client_secret|username)[[:space:]]*=[[:space:]]*)"[^"]*"/\1"***REDACTED***"/Ig'
```

`<REDACT-YAML>` for ConfigMaps / Grafana Agent YAML (`key: value`):

```bash
sed -E 's/((password|token|secret|api_?key|bearer_token|authorization|client_secret)[[:space:]]*:[[:space:]]*).*/\1***REDACTED***/Ig'
```

Redaction rules:
- Mask the **values** of credential-like keys; keep keys, structure, endpoint URLs, job names, and
  scrape configs intact.
- `*_file` / `*_path` references are paths, not secrets — keep them, but **do not** fetch the
  referenced secret files.
- If a config can't be retrieved (no shell, permission denied), note "config not retrievable" rather
  than failing. **Never display a config you could not run through the redactor.**

### Highlight active exporters & log sources (instrumentation coverage)

Don't dump the whole config — extract the **telemetry components** that show what's already
instrumented. From the redacted config, pull the metrics exporters, log sources, and egress
endpoints (one compact pass):

```bash
# Components in use (exporters / scrapers / log sources) + where data is shipped
<redacted-config> | grep -oE '^[a-z._]+ "[a-z_]+"' | sort -u            # e.g. prometheus.exporter.mysql "..."
<redacted-config> | grep -iE 'url =|remote_write|loki\.write|loki\.source|otelcol\.exporter'
```

Map each component to what it instruments, then **correlate with the software detected on that
host** (Step 2/3). If a host runs a service *and* its matching exporter/log source, it is **already
instrumented** for that signal:

| Alloy component | Instruments | "Already instrumented" when host runs… |
|---|---|---|
| `prometheus.exporter.mysql` | MySQL metrics | mysql / mariadb |
| `prometheus.exporter.postgres` | PostgreSQL metrics | postgres |
| `prometheus.exporter.redis` | Redis metrics | redis |
| `prometheus.exporter.unix` | host/node metrics | any Linux host |
| `prometheus.scrape` | scrapes a target's `/metrics` | the scraped app |
| `loki.source.file` / `loki.source.journal` | log collection | the app whose logs are tailed |
| `otelcol.receiver.*` | OTLP traces/metrics/logs | OTel-instrumented apps |

Report a per-host **coverage line**, e.g. *"`mysql-sample-app`: MySQL detected + `prometheus.exporter.mysql`
active → metrics instrumented; `loki.source.file` on MySQL logs → logs instrumented."* Render this
coverage detail **inside that host's own environment section** (the same section as its inventory
table — there is **no** separate "Instrumentation coverage" section; see Step 4). The
inverse — a detected service or host with **no** Alloy/collector (or no matching exporter/log
source) — is a **missing-collector gap**, and that is the **only** kind of finding the Step 4
findings section surfaces. Do **not** turn workload health, backend-reachability guesses, or
legacy-agent migration ideas into findings.

### Kubernetes — standalone Alloy coverage (definitive, config-based)

Use this pass when the cluster runs a **standalone Alloy**: a *single* Alloy instance (one
Deployment/StatefulSet pod, not an operator-managed per-node fleet) that scrapes the cluster. This is
the common local/dev pattern — one `grafana/alloy` pod covering everything.

> **Out of scope for now:** operator-based **Alloy** patterns (Alloy Operator, per-node Alloy
> DaemonSets driven by `PodMonitor`/`ServiceMonitor` CRDs) — a later pass adds these. If such an Alloy
> stack appears alongside a standalone Alloy, enumerate the standalone instance here and note the Alloy
> operator stack as *"coverage not yet analyzed"* rather than guessing.
>
> **Grafana Agent is different — it is end-of-life and unsupported.** Whenever you detect Grafana Agent
> in *any* shape (including operator-managed), do **not** mark it "not yet analyzed": enumerate its
> config + covered services and flag it deprecated — see *Grafana Agent — end-of-life (unsupported)*
> below. Report it **inline**: a per-service coverage column + a one-line callout + at most a findings
> bullet. **Do not give it its own report section.**

Presence (an `alloy` pod in the listing) does **not** tell you *what* it covers. To make a
**definitive** per-pod / per-service instrumented call, connect to the running Alloy, read its live
config, and correlate that config against the workloads enumerated in Step 2.

A standalone Alloy typically scrapes **across namespaces**, so this correlation needs the *full*
cluster inventory. Because parallel mode fans out **one sub-agent per context** (not per namespace),
that agent already sees its whole cluster and runs this pass itself — no separate orchestrator step
is needed.

**1. Identify the standalone Alloy pod and its config path.**
```bash
# Expect a single instance for the standalone pattern (or grep the Step 2 listing for grafana/alloy)
kubectl --context <ctx> -n <ns> get pods -l app.kubernetes.io/name=alloy -o name
# Config path = the --config.file arg (default /etc/alloy/config.alloy)
kubectl --context <ctx> -n <ns> get pod <alloy-pod> -o jsonpath='{.spec.containers[*].args}'
```

**2. Connect to the instance and read its *running* config** — authoritative (reflects what's
actually loaded, not a possibly-stale or unmounted ConfigMap). Read-only `cat`, then redact:
```bash
kubectl --context <ctx> -n <ns> exec <alloy-pod> -- cat /etc/alloy/config.alloy 2>/dev/null | <REDACT>
# Fallback if no shell/cat: the mounted ConfigMap (get configmap ... -o jsonpath='{.data}' | <REDACT-YAML>)
```

**3. Enumerate what the config collects.** From the redacted config, pull:
- **Static targets** — `prometheus.scrape` blocks with an explicit `targets = [...]` (host:port you
  can match directly to a workload).
- **Dynamic discovery** — `discovery.kubernetes "<role>"` (role = `pod`/`service`/`endpoints`) plus
  the `discovery.relabel` / scrape `rule { ... }` **keep-rules** that select by namespace, label, or
  annotation (e.g. keep only `__meta_kubernetes_pod_annotation_prometheus_io_scrape == "true"`).
- **Log pipelines** — `loki.source.kubernetes` / `loki.source.file` and their discovery, which decide
  whose logs are shipped.
- **Egress** — `prometheus.remote_write` / `loki.write` endpoints (URLs preserved, creds redacted).

**4. Correlate against the Step 2 workload inventory → definitive call.** For each enumerated
pod/service, decide per signal (metrics, logs):
- **Static target match** → that workload is **instrumented** — definitive.
- **Dynamic discovery** → evaluate the keep-rules against the workload's namespace/labels/annotations.
  Step 2 only grabs ns/name/image, so when the config selects by label/annotation, fetch those fields
  for the candidate pods:
  ```bash
  kubectl --context <ctx> -n <ns> get pods \
    -o custom-columns='NS:.metadata.namespace,POD:.metadata.name,LABELS:.metadata.labels,ANN:.metadata.annotations'
  ```
  A workload whose labels/annotations satisfy the keep-rules is **instrumented**; one that doesn't is
  **not**.
- **Ground-truth option (most definitive when relabeling is complex).** Port-forward to the Alloy HTTP
  UI and read the **live discovered/active targets** instead of re-deriving them from rules:
  ```bash
  kubectl --context <ctx> -n <ns> port-forward <alloy-pod> 12345:12345 &   # read-only; kill when done
  # inspect the running components and their active targets at http://localhost:12345
  ```
  The set of active scrape targets is the authoritative list of what's instrumented; any Step 2
  workload absent from it is a gap.

**5. Report the call — with the same coverage detail as the VM approach.** Don't stop at yes/no:
describe *what level* of coverage Alloy provides, mirroring the VM coverage table (service →
exporter/log source → coverage). Use the same component→instruments mapping from *Highlight active
exporters & log sources* above, and distinguish the levels:
- **host/node-level** — `prometheus.exporter.unix` (node metrics), node/journal logs;
- **app/service-level** — `prometheus.exporter.mysql` / `.postgres` / `.redis`, a `prometheus.scrape`
  of an app's `/metrics`, `loki.source.file` on an app's logs;
- **agent self-monitoring only** — `prometheus.exporter.self` (Alloy's own internal metrics), which is
  *not* coverage of any workload.

Produce a K8s coverage table in the same shape as the VM one — e.g. `| Target | Exporter / log source
| Coverage |` — plus a per-workload metrics **yes/no** + logs **yes/no** call, and the **basis** for
each (e.g. *"matched `discovery.kubernetes` keep-rule on annotation `prometheus.io/scrape`"*, *"explicit
`prometheus.scrape` target"*, *"live target in Alloy UI"*, *"only `prometheus.exporter.self` wired —
self-metrics, instruments nothing else"*). Place this coverage table and its definitive call
**within the Kubernetes section** of the report (directly beneath that context's inventory table),
not in a separate section — summarize the config component graph to a few lines rather than dumping
it. Feed every uninstrumented workload into the Step 4 missing-collector gaps.

### Grafana Agent — end-of-life (unsupported)

**Grafana Agent is deprecated and end-of-life; we do not support it.** Whenever it is detected — in any
shape — flag it as deprecated/unsupported **and** enumerate what it covers (so existing coverage isn't
lost in a migration to Alloy). Detect it by:
- **VM / container:** a `grafana-agent` service, or an image/name matching `grafana/agent`,
  `grafana-agent`, `agent:v0.*` (its config: `/etc/grafana-agent.yaml` or `/etc/agent/agent.yaml`).
- **Kubernetes, standalone:** a pod/image `grafana/agent` — read its running config like the standalone
  Alloy pass.
- **Kubernetes, operator-managed:** the `grafana-agent-operator` image and the `monitoring.grafana.com`
  CRDs. Its config is *assembled from CRs*, so enumerate coverage from them rather than a single file:
  ```bash
  kubectl --context <ctx> --request-timeout=8s get grafanaagent,metricsinstance,logsinstance,integration,podlogs -A
  # what gets scraped: monitors selected by each MetricsInstance's *Selector labels
  kubectl --context <ctx> --request-timeout=8s get servicemonitors,podmonitors,probes -A
  # node/host metrics come from Integration kind=node_exporter (allNodes ⇒ DaemonSet on every node)
  # remote_write / logs egress live on the MetricsInstance.spec.remoteWrite / LogsInstance.spec.clients
  ```
  Map `Integration node_exporter` → host/node metrics; selected `ServiceMonitor`/`PodMonitor`/`Probe`
  → those app/platform targets; `LogsInstance` + `PodLogs` → logs (zero `PodLogs` ⇒ no logs).

**Report it inline, never as its own report section:** a per-service *Instrumented (Grafana Agent —
EOL)* coverage column (Step 4), a one-line callout in the environment's existing section, and a single
Grafana Agent EOL bullet under findings. Do not analyze it more deeply than Alloy or turn it into a
migration plan.

## Step 4 — Output format

Lead with a one-line summary per environment (e.g. *"Kubernetes (k3d-cloud-onboarding-cluster): 38
pods across 6 namespaces"*). Then, for each environment, a table grouped by **namespace**, then
**category**:

| Namespace | Category | Software | Image / Version | Instrumented (standalone Alloy) | Notes |
|---|---|---|---|---|---|
| default | Observability | loki | grafana/loki:3.x | No | |
| default | Observability | alloy | grafana/alloy:v1.x | Self-metrics only | Alloy: standalone |
| auth | Databases | mysql | mysql:8.0 | No | |
| dbs › ubuntu | Observability | grafana | grafana/grafana:1.x | No | |

Represent nested namespaces as `<outer> › <inner-project>`. Add an **Alloy installed** column or a
per-namespace note (report it at both the outer and nested level). For very large or deeply nested
result sets, an indented tree (Environment → Namespace → Nested namespace → Category → software) is
an acceptable alternative.

**The `Software` column holds the bare software name only.** Any qualifier past the name — a pod count,
`standalone`, `EOL / unsupported`, `+ replica`, etc. — goes in a dedicated **Notes** column, never
appended to the software name. **Prefix collector-specific notes with the collector**, e.g.
`Alloy: standalone`, `Grafana Agent: operator-managed ×3; EOL / unsupported`, so the note's subject is
unambiguous.

**For Kubernetes, add a per-service `Instrumented` column per analyzed collector**, populated from the
coverage pass (Step 3). The point is to expose *individual* gaps — a service sitting in an otherwise
well-instrumented namespace/context that is itself not scraped. Keep cells concise (e.g. `Metrics`,
`Metrics + logs`, `Self-metrics only`, `No`), and:
- **One column per collector actually analyzed**, titled for it (e.g. *Instrumented (standalone
  Alloy)*). If Grafana Agent (EOL) is also present, add a second *Instrumented (Grafana Agent — EOL)*
  column beside it. Mark the collector's own pods `n/a`.
- Add a one-line note that `No` means "not covered by that collector," not "no telemetry at all." For
  *Alloy* operator patterns not yet analyzed, mark those rows `n/a (operator stack)`; Grafana Agent is
  **not** deferred — it's the EOL edge case (below).
- Keep the inventory `Instrumented` cells concise (`Metrics + logs`, `Self-metrics only`, `No`); put
  the *detailed* per-service coverage (which exporter, host- vs app-level, logs) **inline in that
  environment's own section**, never as its own report section — see *Per-environment coverage* below.

### Per-environment coverage — fold it in, no standalone section

**There is no separate "Instrumentation coverage" section.** Each environment's coverage detail lives
**inside that environment's own section**, beside its inventory, so the reader never cross-references.
Convey it as concisely as possible without dropping any inventory-table columns:
- **Kubernetes:** the per-collector `Instrumented (...)` columns in the inventory table carry the
  per-service call; beneath that table add the short coverage-level table (`| Target | Exporter / log
  source | Coverage |`) and the one-paragraph definitive call (config component graph summarized to a
  few lines, not dumped).
- **Multipass:** **merge** coverage into the single inventory table by adding `Exporter / log source`
  and `Coverage` columns — keep every existing column. The shared egress endpoints
  (`remote_write` / `loki.write` URLs) go in a one-line note above or below the table:
  `| Namespace (VM) | Category | Software | Detail | Alloy installed | Exporter / log source | Coverage |`
- **Docker:** the inline `Alloy: n/a` note under the Docker table is sufficient; no extra coverage block.

**This is a plain-text inventory, not a health audit — strict reporting rules:**
- **No Status column.** Never render a workload's run state (`Running`, `CrashLoopBackOff`, `Up`,
  restart counts, etc.) in any table. Status is collected only to scope what to enumerate (Step 2).
- **No emphasis or warning markup on values.** Write `alloy`, not `**alloy**`; `grafana/alloy:v1.14.2`,
  not `**v1.14.2**`. No `⚠️` or other emoji anywhere in tables or summaries.
- **One-line summaries describe what's present** (counts, stacks, Alloy presence) — never workload
  health.
- **Only list reachable, enumerated contexts** — in the Kubernetes section, the one-line summary, and
  the scope line alike. Do **not** enumerate unreachable/stopped contexts by name. If *some* clusters
  are reachable, report only those (a single brief aside like *"(N other contexts unreachable)"* is
  fine — never the list of names). If **no** Kubernetes cluster is reachable, omit per-context detail
  entirely and give a one-line summary like Docker's empty note, e.g. *"Kubernetes: no reachable
  clusters."* The same applies to any environment type with nothing available.
- Other scope caveats (System/OS services filtered, VMs skipped by request) belong in a single italic
  line under the header, **not** as findings.

### Findings / gaps — missing-collector gaps + the Grafana Agent EOL flag

The findings section lists **only**:
- detected services or hosts that have **no collector** (a missing-collector gap), so the reader knows
  where telemetry coverage is absent; and
- **one bullet flagging Grafana Agent as end-of-life / unsupported** when it is present (see the edge
  case below) — state that its coverage must move to Alloy, but keep it to a single bullet.

It must **not** include:
- workload health (crashing/restarting pods, down services),
- backend-reachability diagnosis ("configured but the backend looks unreachable"),
- broader migration project planning beyond the single Grafana Agent EOL bullet,
- stopped or unreachable targets (those are noted once in the scope line, not as findings).

## Best practices

- **Read-only only.** Never start/stop/restart/apply/delete or open a mutating shell — including
  during the Alloy presence check and config capture (only ever `cat`/`get` configs).
- **Inventory, not health audit.** Report what's running and its collector coverage only. Never put
  workload status, restart counts, backend-reachability guesses, or migration recommendations in the
  output, and never decorate values with bold/emphasis or warning emoji (see Step 4). The findings
  section carries missing-collector gaps and nothing else.
- **Never emit raw credentials.** Always pipe any captured Alloy/Agent config through the redaction
  filter before saving or displaying it; if you can't redact it, don't show it.
- **Recurse into nested runtimes.** When a VM or container runs its own Docker/Compose, enumerate the
  inner containers as a nested namespace and run the Alloy presence check on each. Cap depth and skip
  already-seen container IDs to avoid cycles. Detect nested Alloy by name/image when there's no shell.
- **Never assume scope.** Always list and confirm which context(s) / VM(s) / Compose project(s) to
  enumerate before running anything in Step 2.
- **Offer parallelism for large scopes.** After counting contexts/VMs, prompt the user; if they
  opt in, fan out one sub-agent per Kubernetes context + one for Docker + one for Multipass
  (concurrent), each returning a compact structured inventory the orchestrator merges.
- **Default to the current kubectl context only after confirmation**, and make multi-context
  enumeration explicit and opt-in.
- **Skip System / OS services** unless the user explicitly asks for them.
- **Degrade gracefully.** Note unreachable or erroring environments and continue; don't abort the
  whole inventory because one target is down.
