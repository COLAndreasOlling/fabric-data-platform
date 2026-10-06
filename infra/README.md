# Infrastructure as code

Three Terraform configurations, each with its own state, run in this order:

| # | Folder | Creates | Runs as |
|---|---|---|---|
| 1 | `capacities/bootstrap/` | Executor app registration + service principal, security group, GitHub OIDC trust, resource group, Contributor role, Fabric tenant settings (opt-in) | **You** (admin, `az login`) - once |
| 2 | `capacities/` | 2 Fabric capacities (dev, prod) | Executor service principal |
| 3 | `fabric/` | 6 workspaces, lakehouse, warehouses, workspace identities, cross-workspace access | Executor service principal |

## What `fabric/` creates

| Workspace | Items |
|---|---|
| DataEngineeringDev / DataEngineeringProd | `LH_Bronze` (lakehouse, schemas enabled), `WH_Silver_Sources`, `WH_Silver_Models`, `WH_Gold_DataEstate` |
| ReportingHubDev / ReportingHubProd | Nothing - semantic models come from Git / deployment |
| ReportingInsightsDev / ReportingInsightsProd | Nothing - reports come from Git / deployment |

Every workspace gets a **workspace identity** (a Fabric-managed service principal).
Cross-workspace access, within the same environment only:

| Workspace identity of | Gets role | On |
|---|---|---|
| ReportingHub | Viewer | DataEngineering (read the gold warehouse) |
| ReportingInsights | Viewer | ReportingHub (use the semantic models) |

Change this with the `cross_workspace_access` variable. Dev identities never get access to Prod.

## Ownership and admin rights

- Fabric items are owned by the identity that creates them. `capacities/` and
  `fabric/` **refuse Azure CLI / personal logins**, so everything is created and
  owned by the **executor service principal** (`sp-fabric-terraform`).
- Fabric doesn't allow items to be owned by themselves or by a workspace identity;
  a dedicated service principal is the closest non-personal owner.
- The executor creates the workspaces and so becomes **Admin** of all of them
  automatically, and is added as **capacity admin** in `capacities/`.
- The app registration, service principal and group are created **without owners**
  by default (`entra_owners`). Check *Owners* in Entra after bootstrap - remove
  yourself if Entra added you.
- Give people access through an **Entra group** via `additional_role_assignments`
  (see `fabric/terraform.tfvars.example`), never as owners.

## Case-insensitive collation

All SQL artifacts are created case insensitive (`Latin1_General_100_CI_AS_KS_WS_SC_UTF8`):

- **Warehouses** get the collation set explicitly at creation.
- **Lakehouse SQL endpoints** always take the workspace's *Data Warehouse collation*
  setting, which Fabric only exposes in the portal (no API). So `fabric/` runs in
  two passes:
  1. First `apply` creates the workspaces and warehouses, and **skips lakehouses**
     (you'll see a warning).
  2. In each workspace: **Workspace settings → Data Warehouse → Collations → Case
     insensitive**. Do all six, so anything created later is case insensitive too.
  3. Set `workspace_collation_confirmed = true` in `fabric/terraform.tfvars` and
     `apply` again to create the lakehouses.
- Collation can never be changed after an item is created.
- To change the setting you need Admin/Member/Contributor on the workspace - add
  your admin group through `additional_role_assignments` before step 2.

## 1. Bootstrap (once, as an admin)

You need: **Application Administrator** (or Cloud Application Administrator) and
**Groups Administrator** in Entra, **Owner** (or User Access Administrator) on the
subscription, and **Fabric Administrator** if you let it manage tenant settings.

```powershell
az login
cd infra/capacities/bootstrap
Copy-Item terraform.tfvars.example terraform.tfvars   # set subscription_id
terraform init
terraform plan
terraform apply
```

Tenant settings: with `manage_fabric_tenant_settings = true`, the executor group
is **added** to *Service principals can create workspaces, connections, and
deployment pipelines* and *Service principals can call Fabric public APIs*.
Existing groups are kept; settings already enabled for the whole organization are
left alone. Otherwise, a Fabric admin adds the group `sg-fabric-terraform-executors`
to those two settings by hand.

## 2. and 3. Running as the executor

Set the credentials in the terminal (never in files):

```powershell
cd infra/capacities/bootstrap
$env:ARM_TENANT_ID     = terraform output -raw tenant_id
$env:ARM_CLIENT_ID     = terraform output -raw client_id
$env:ARM_CLIENT_SECRET = terraform output -raw client_secret

$env:FABRIC_TENANT_ID     = $env:ARM_TENANT_ID
$env:FABRIC_CLIENT_ID     = $env:ARM_CLIENT_ID
$env:FABRIC_CLIENT_SECRET = $env:ARM_CLIENT_SECRET
```

Capacities (they cost money while running - pause them when idle):

```powershell
cd ../                                               # infra/capacities
Copy-Item terraform.tfvars.example terraform.tfvars   # set subscription_id
terraform init
terraform plan
terraform apply
```

Fabric:

```powershell
cd ../../fabric                                      # infra/fabric
terraform init
terraform plan
terraform apply
```

If you already have capacities, set `environments` in `fabric/terraform.tfvars`
to their display names and skip step 2. Capacities must be **running**, and the
executor must be a capacity admin or contributor.

GitHub Actions uses OIDC instead of the secret: set `ARM_USE_OIDC=true` /
`FABRIC_USE_OIDC=true` with the tenant and client IDs. The trust is set up for
`main` and pull requests on `COLAndreasOlling/fabric-data-platform`.

## State

State is local (`terraform.tfstate`, git-ignored) for now. The bootstrap state
contains the client secret - never commit or share it. Before running from GitHub
Actions or sharing with colleagues, move state to an Azure Storage backend.

## Known limits

- Workspace **Viewer** on DataEngineering lets the ReportingHub identity read all
  items there (including `LH_Bronze` through its SQL endpoint). The Fabric
  provider doesn't support item-level permissions yet; tighten later by sharing
  only `WH_Gold_DataEstate` or using OneLake data access roles.
- Lakehouse schemas and collations can't be changed after creation.
- Tenant setting API names (`ServicePrincipalAccessGlobalAPIs`,
  `ServicePrincipalAccessPermissionAPIs`) are checked when you plan; adjust
  `fabric_tenant_settings` if Microsoft renames them.
