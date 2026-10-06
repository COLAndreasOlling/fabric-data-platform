# Infrastructure as code

Two independent Terraform configurations, each with its own state:

| Folder | Creates | Provider |
|---|---|---|
| `capacities/` | Resource group + 2 Fabric capacities (dev, prod) in Azure | `hashicorp/azurerm` |
| `fabric/` | 6 workspaces, lakehouse, warehouses, workspace identities, cross-workspace access | `microsoft/fabric` |

Run `capacities/` first (once), then `fabric/` as often as needed.

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

- Fabric items are owned by the identity that creates them. Both providers are
  configured to **refuse Azure CLI / personal logins**, so everything is created
  and owned by a **service principal** (the "executor").
- Fabric doesn't allow items to be owned by themselves or by a workspace identity;
  a dedicated service principal is the closest non-personal owner.
- The executor creates the workspaces and so becomes **Admin** of all of them
  automatically.
- The executor is added as **capacity admin** in `capacities/`, so it can assign
  workspaces to the capacities.
- Give people access through an **Entra group** via `additional_role_assignments`
  (see `fabric/terraform.tfvars.example`), never as owners.

## One-time setup

### 1. Create the executor service principal
In the Entra admin center: **App registrations → New registration** (e.g.
`sp-fabric-terraform`). Note the **Application (client) ID** and **Tenant ID**,
then create a **client secret** (for local runs). For GitHub Actions, add a
**federated credential** instead of using the secret.

### 2. Fabric tenant settings (Fabric admin portal → Tenant settings)
- *Service principals can use Fabric APIs* - enabled (ideally for a security group containing the SP)
- *Service principals can create workspaces, connections, and deployment pipelines* - enabled
- *Users can create Fabric items* - enabled

### 3. Azure permissions (for `capacities/`)
Give the service principal **Contributor** on the subscription or resource group.

## Running locally

Credentials go in environment variables for the current terminal only - never
in files:

```powershell
$env:ARM_TENANT_ID     = "<tenant-id>"
$env:ARM_CLIENT_ID     = "<client-id>"
$env:ARM_CLIENT_SECRET = "<secret>"

$env:FABRIC_TENANT_ID     = $env:ARM_TENANT_ID
$env:FABRIC_CLIENT_ID     = $env:ARM_CLIENT_ID
$env:FABRIC_CLIENT_SECRET = $env:ARM_CLIENT_SECRET
```

Capacities (when you're ready - they cost money while running):

```powershell
cd infra/capacities
Copy-Item terraform.tfvars.example terraform.tfvars   # then set subscription_id
terraform init
terraform plan
terraform apply
```

Fabric:

```powershell
cd infra/fabric
terraform init
terraform plan
terraform apply
```

If you already have capacities, set `environments` in `fabric/terraform.tfvars`
to their display names and skip `capacities/`. Capacities must be **running**.

## State

State is local (`terraform.tfstate`, git-ignored) for now. Before running from
GitHub Actions or sharing with colleagues, move it to an Azure Storage backend.

## Known limits

- Workspace **Viewer** on DataEngineering lets the ReportingHub identity read all
  items there (including `LH_Bronze` through its SQL endpoint). The Fabric
  provider doesn't support item-level permissions yet; tighten later by sharing
  only `WH_Gold_DataEstate` or using OneLake data access roles.
- Lakehouse schemas and warehouse collation can't be changed after creation.
