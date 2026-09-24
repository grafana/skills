---
name: hol-guard-agent-safety
license: Apache-2.0
description: >
  Protect local AI coding-agent sessions before Grafana-changing command and tool work with HOL Guard.
  Use when an agent may edit Grafana provisioning, install plugins, call write APIs, change dashboards or data sources,
  or handle privileged Grafana operations from a supported local coding-agent harness.
---

# HOL Guard Agent Safety for Grafana

Use HOL Guard as the local agent-runtime boundary before a coding agent performs Grafana work that can mutate
configuration, dashboards, data sources, plugins, or other operational state.

HOL Guard protects the supported local agent harness. It does not run inside Grafana, replace Grafana RBAC,
service-account permissions, provisioning review, backups, or environment targeting.

## Protect the agent session

Install HOL Guard in an isolated Python application environment:

```bash
pipx install hol-guard
```

Detect the current coding-agent harness and use the exact harness identifier returned by HOL Guard:

```bash
hol-guard detect --json
hol-guard install <detected-harness>
hol-guard run <detected-harness> --dry-run
hol-guard run <detected-harness>
```

Do not guess the harness name. If detection reports no supported harness, do not claim that the current session is
protected.

Before doing privileged Grafana work, verify the installed protection:

```bash
hol-guard doctor <detected-harness> --json
hol-guard status
```

If Guard reports a deny, review-required state, timeout, malformed result, unavailable runtime, or other error,
stop the protected workflow. Do not fall back to an unprotected agent session just to complete the Grafana action.

## Keep Grafana-native safeguards

HOL Guard is additive to Grafana's own controls. Keep the normal Grafana safety checks in place:

- verify the target Grafana instance and organization before a write;
- use the least-privileged service account or user role that can perform the task;
- review provisioning and dashboard changes before applying them;
- preserve backups, dry runs, or export snapshots when the workflow supports them;
- verify the resulting Grafana state after the change.

For Grafana OSS provisioning, dashboards, data sources, RBAC, and service-account workflows, use the
`grafana-oss` skill alongside this one. For Grafana Cloud account and access controls, use the relevant
`grafana-cloud` skills.

## Review Guard decisions

When HOL Guard pauses an action for review, inspect the pending decision and evidence rather than bypassing the
protected session. Use the Guard approval, receipt, evidence, status, and doctor flows documented by the installed
HOL Guard version.

A side-effect-free `hol-guard command test ... --json` result may be useful for inspecting a specific shell command,
but it is command inspection only. Do not present it as the final runtime policy decision or as proof that a Grafana
operation was approved.

## Scan agent artifacts before trust

HOL Guard's separate `plugin-scanner` CLI can inspect Agent Skills, MCP packages, AI plugins, and agent repositories
before installation or trust. Use it for agent ecosystem artifacts, not as a Grafana plugin vulnerability scanner.

```bash
pipx install plugin-scanner
plugin-scanner scan <path-or-repository>
```

A clean scan is evidence, not a guarantee of safety. Keep normal source review and dependency controls.

## Security boundary

This skill makes no claim that HOL Guard intercepts Grafana server-side execution, Grafana Cloud control-plane
operations, or every Grafana CLI/API command. The supported enforcement boundary is the local coding-agent harness
that HOL Guard detects, installs into, and runs.

HOL Guard source: https://github.com/hashgraph-online/hol-guard
