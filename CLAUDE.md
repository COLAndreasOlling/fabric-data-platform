# CLAUDE.md

Terraform for a Microsoft Fabric data platform: an executor service principal,
Key Vault, Fabric capacities, six workspaces (DataEngineering / ReportingHub /
ReportingInsights × Dev / Prod), a lakehouse, warehouses and cross-workspace
access. Fabric content (notebooks, models, reports) lives in `fabric/`, synced by
Fabric Git integration.

- Step-by-step deployment: `docs/terraform-setup-guide.md` — follow it, don't improvise.
- Reference (what's created, naming, ownership, limits): `infra/README.md`.

## Layout

| Path | Terraform root | Runs as |
|---|---|---|
| `infra/capacities/bootstrap/` | Service principal, group, resource groups, Key Vault, writes `infra/platform.json` | The user (`az login`) |
| `infra/capacities/` | Fabric capacities | Executor service principal |
| `infra/fabric/` | Workspaces, items, role assignments | Executor service principal |
| `infra/platform.json` | Shared names/IDs (no secrets), read by the last two | Committed |
| `fabric/` | Fabric Git integration output | **Never edit by hand** |

Run order: bootstrap → tenant settings (manual) → capacities → fabric pass 1 →
collation (manual) → fabric pass 2. Any part can be skipped in an existing
environment — see "Using an existing environment" in the guide.

## Rules when running Terraform

- **Plan, show, confirm, apply the saved plan.** Always
  `terraform plan -out tfplan`, summarise adds / changes / destroys for the user,
  wait for an explicit yes, then `terraform apply tfplan`. Never `-auto-approve`.
  Call out loudly any `destroy` or `must be replaced` on a lakehouse, warehouse,
  workspace or Key Vault — that loses data.
- **Right identity per root.** Bootstrap runs as the user: clear `ARM_*` and
  `FABRIC_*` env vars first. `infra/capacities/` and `infra/fabric/` must run as
  the service principal: the providers set `use_cli = false` on purpose so no
  personal account owns Fabric items. Never "fix" an auth error by enabling
  `use_cli` — load the credentials (guide step 3) instead.
- **Credentials only in env vars of the same command/session.** Read them from
  Key Vault with `az keyvault secret show` inside the command that runs
  Terraform. Never print, echo, log or write the client secret to a file.
- **No interactive prompts in Claude's shell.** Terraform prompts (bootstrap
  naming inputs) don't work non-interactively: ask the user for the values and
  put them in that root's `terraform.tfvars` (git-ignored).
- **Signing in is the user's.** Start `az login --tenant <tenant>` if asked, but
  the user completes it in the browser. Never enter passwords or tokens.
- **Manual steps stay manual.** Don't change Fabric tenant settings or the
  workspace collation for the user — tell them what to set and wait (guide steps
  2 and 6).
- **Costs.** Capacities bill per hour while running. Confirm before creating or
  resuming them; offer to pause them afterwards.
- **Check which tenant/subscription before every apply**
  (`az account show`) and name it in the confirmation.

## Rules when changing the code

- Validate every root you touch: `terraform fmt` and `terraform validate`.
  `infra/capacities/` and `infra/fabric/` need `infra/platform.json`; if it's
  missing, validate with a temporary copy of `infra/platform.example.json` and
  delete it afterwards.
- Check resource arguments against the installed provider
  (`terraform providers schema -json`) rather than from memory — the Fabric
  provider changes often.
- Don't break these design decisions without the user agreeing:
  - Fabric items are created and owned by the executor service principal.
  - The executor becomes workspace Admin by creating the workspaces (no explicit
    assignment — Fabric rejects a duplicate).
  - The orchestrator (the user signed in to `az`) is **always** workspace Admin
    (`orchestrator_admin`, looked up with `az ad signed-in-user show`). Never
    remove this; in CI set `orchestrator_object_id`.
  - Naming: `<env>-<company>-<region>-dp-<version>-da[-<resource>]`; capacity
    names have the hyphens removed (Azure allows only `[a-z0-9]`).
  - SQL artifacts are case insensitive (`Latin1_General_100_CI_AS_KS_WS_SC_UTF8`);
    lakehouses wait for `workspace_collation_confirmed = true`.
  - Bootstrap never touches Fabric tenant settings.
  - Cross-workspace access never crosses environments.
- Update `infra/README.md` and the guide when behaviour changes.

## Never commit

`*.tfstate*` (the bootstrap state contains the client secret), `terraform.tfvars`,
`tfplan`, `.terraform/`, secrets or customer data. `.terraform.lock.hcl`,
`*.tfvars.example` and `infra/platform.json` are committed.

## Environment notes

- Windows / PowerShell 5.1. After installing tools, refresh `PATH` in the
  session: `$env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')`.
- Columbus Data & AI DK's code of conduct applies. Deploying into a client tenant
  requires the client's agreement; keep client code in a repo the client
  (or Columbus) owns.
