# fabric-data-platform

Infrastructure as code and source control for a Microsoft Fabric data platform.

## Layout

| Folder | What goes there |
|---|---|
| `infra/` | Terraform: executor service principal, Key Vault, Fabric capacities, workspaces, lakehouse, warehouses and access. See [infra/README.md](infra/README.md). |
| `fabric/` | Fabric workspace items (notebooks, pipelines, semantic models, reports). **Managed by Fabric Git integration — don't edit by hand unless you know what you're doing.** |
| `docs/` | Guides, notes and architecture decisions. |
| `scripts/` | Helper scripts (e.g. Python, PowerShell) used outside Fabric. |

## Getting started

**Deploy the platform** — follow [docs/terraform-setup-guide.md](docs/terraform-setup-guide.md)
step by step. It creates the capacities, the six workspaces and their items, and
connects the Dev workspaces to the customer's existing GitHub or Azure DevOps
repository (it asks for the details).

## The platform

| Workspace | Purpose |
|---|---|
| DataEngineeringDev / Prod | `LH_Bronze`, `WH_Silver_Sources`, `WH_Silver_Models`, `WH_Gold_DataEstate` |
| ReportingHubDev / Prod | Shared semantic models on the gold layer |
| ReportingInsightsDev / Prod | Reports on the ReportingHub semantic models |

## Connecting a workspace to Git by hand

Terraform connects the Dev workspaces for you. Use this only for a workspace
Terraform doesn't manage. Connect **Dev** workspaces only; Prod is updated by
deployment, not edited directly.

1. Create a **fine-grained personal access token** on GitHub:
   Settings → Developer settings → Personal access tokens → Fine-grained tokens.
   Give it access to this repository only, with **Contents: Read and write**.
2. In Fabric, open the workspace → **Workspace settings** → **Git integration** → **GitHub**.
3. Add a GitHub account: paste the token and this repo's URL.
4. Choose branch `main` and a Git folder per workspace type, e.g.
   `fabric/DataEngineering`, `fabric/ReportingHub`, `fabric/ReportingInsights`,
   then **Connect and sync**.

From then on, use the **Source control** button in the workspace to commit
changes from Fabric to GitHub, or pull updates from GitHub into Fabric.

> If GitHub isn't offered as an option, a Fabric admin must enable the tenant
> setting *"Users can sync workspace items with GitHub repositories"*.

## Day-to-day workflow

1. Create a branch for a change (in Fabric: Source control → Branch out, or locally `git switch -c my-change`).
2. Make changes in Fabric and commit them from the Source control pane.
3. Open a pull request on GitHub, review, and merge to `main`.
4. Run `git pull` locally to get the latest.

## Never commit

Passwords, connection strings, keys, tokens, Terraform state (`*.tfstate`),
real `terraform.tfvars` files or customer data. Secrets live in the platform's
Azure Key Vault; local secrets go in `.env` (ignored).
