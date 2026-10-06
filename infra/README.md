# Infrastructure as code

> **Deploying?** Follow the step-by-step [Terraform setup guide](../docs/terraform-setup-guide.md).
> This page is the reference: what gets created, naming, ownership and limits.
> Have an existing environment? See [Using an existing environment](../docs/terraform-setup-guide.md#using-an-existing-environment).

Three Terraform configurations, each with its own state, run in this order:

| # | Folder | Creates | Runs as |
|---|---|---|---|
| 1 | `capacities/bootstrap/` | Executor app registration + service principal, GitHub OIDC trust, security group, resource groups, Contributor roles, Key Vault with the executor's credentials, `platform.json` | **You** (`az login`) - once, and again to rotate the secret |
| 2 | `capacities/` | Fabric capacities (Dev, Prod) | Executor service principal |
| 3 | `fabric/` | 6 workspaces, lakehouse, warehouses, workspace identities, cross-workspace access, Git connection for the Dev workspaces | Executor service principal |

`infra/platform.json` is written by bootstrap and read by the other two. It holds
names and IDs only (no secrets) and should be committed. Without bootstrap (existing
environment), create it by hand from `platform.example.json`.

## Naming

`<env>-<company>-<region>-dp-<version>-da[-<resource>]`, prompted when you run bootstrap:

| Resource | Example |
|---|---|
| Resource group | `p-cg-we-dp-01-da` |
| Key Vault | `p-cg-we-dp-01-da-kv` |
| Fabric capacity | `pcgwedp01dafab` - Azure only allows lowercase letters and digits in capacity names, so the hyphens are dropped |
| Executor service principal | `cg-we-dp-01-da-sp-terraform` (shared by all environments) |
| Executor group | `cg-we-dp-01-da-sg-terraform-executors` |

Environment letters: Dev = `d`, Prod = `p` (`environments` variable). Region
abbreviations are in `capacities/bootstrap/main.tf` (`westeurope` = `we`).

## What `fabric/` creates

| Workspace | Items |
|---|---|
| DataEngineeringDev / DataEngineeringProd | Folders `100_Bronze` (`LH_Bronze`, lakehouse with schemas), `200_Silver` (`WH_Silver_Sources`, `WH_Silver_Models`), `300_Gold` (`WH_Gold_DataEstate`), `400_DataTransformation` (empty — for pipelines, notebooks, copy jobs) |
| ReportingHubDev / ReportingHubProd | Nothing - semantic models come from Git / deployment |
| ReportingInsightsDev / ReportingInsightsProd | Nothing - reports come from Git / deployment |

Every workspace gets a **workspace identity** (a Fabric-managed service principal).
Cross-workspace access, within the same environment only:

| Workspace identity of | Gets role | On |
|---|---|---|
| ReportingHub | Viewer | DataEngineering (read the gold warehouse) |
| ReportingInsights | Viewer | ReportingHub (use the semantic models) |

Change this with the `cross_workspace_access` variable. Dev identities never get access to Prod.

Folders and item placement are set by `data_engineering_folders`, `lakehouses`
and `warehouses` (item name => folder). Moving an item to another folder is an
in-place update — the item and its data are kept. Folders are a **preview**
resource in the Fabric provider, so `preview = true` is set in `providers.tf`
and every plan shows a preview warning.

## Git integration

The **Dev** workspaces are connected to the customer's existing repository
(`git_environments`, default `["Dev"]`); Prod gets content through deployment.

| Variable | Asked when missing | Example |
|---|---|---|
| `git_provider` | yes | `GitHub` / `AzureDevOps` |
| `git_repository_url` | yes | `https://github.com/<owner>/<repo>`, `https://dev.azure.com/<org>/<project>/_git/<repo>` |
| `git_branch` | yes | `main` (must exist) |
| `git_folder` | yes | `/fabric` → `/fabric/DataEngineering`, `/fabric/ReportingHub`, `/fabric/ReportingInsights` |
| `git_secret` | loaded by `Load-Credentials.ps1` | GitHub token / executor client secret |

- **GitHub**: a Fabric connection (`GitHubSourceControl`) with a personal access
  token, stored in Key Vault as `git-token` by `infra/Save-GitToken.ps1`.
- **Azure DevOps**: a Fabric connection (`AzureDevOpsSourceControl`) authenticated
  as the executor service principal, which must be added to the Azure DevOps
  organization and project.
- The connection is owned by the executor; the orchestrator gets the *User* role
  on it so they can use it from the Source control pane.
- `git_secret` is an **ephemeral** variable passed only to write-only arguments:
  it never ends up in the Terraform state. Bump `git_secret_version` after a
  new token/secret.
- The URL is parsed into owner/organization/project/repository and checked
  against `git_provider` — nothing is guessed.
- Missing workspace folders are created first by `Initialize-GitFolders.ps1`
  (run by `terraform_data.git_folders`): one `README.md` per folder, committed to
  the branch. Fabric's API won't connect to a folder that doesn't exist. Existing
  folders are untouched; the repository and branch are never created. Set
  `powershell = "pwsh"` where Windows PowerShell isn't available (Linux CI).
- Azure DevOps: the service principal needs **Basic** access (Stakeholder can't
  use Repos) and Contribute on the repository (e.g. project Contributors).
- `git_initialization_strategy` defaults to `PreferWorkspace`: connecting never
  overwrites workspace items with repository content.

## Credential scripts

| Script | What it does |
|---|---|
| `. ./infra/Load-Credentials.ps1 -GitProvider <GitHub\|AzureDevOps>` | Checks you're signed in to the tenant in `platform.json`, loads the executor's credentials and `TF_VAR_git_secret` from Key Vault into the session. Parameters for existing environments: `-KeyVaultName`, `-ClientSecretName`, `-GitTokenSecretName`. |
| `./infra/Save-GitToken.ps1` | Asks for a GitHub token (hidden) and its expiry date and stores it in Key Vault as `git-token`. |

## Ownership and admin rights

- Fabric items are owned by the identity that creates them. `capacities/` and
  `fabric/` **refuse Azure CLI / personal logins**, so capacities, workspaces and
  items are created and owned by the **executor service principal**.
- Fabric doesn't allow items to be owned by themselves or by a workspace identity;
  a dedicated service principal is the closest non-personal owner.
- The executor creates the workspaces and so becomes **Admin** of all of them
  automatically, and is added as **capacity admin** in `capacities/`.
- The **orchestrator** — the person signed in to Azure CLI (`az login`) while
  Terraform runs — is always added as workspace **Admin**, so they can find and
  manage the workspaces. Terraform looks the account up with
  `az ad signed-in-user show`. Where az is signed in as a service principal
  (GitHub Actions), set `orchestrator_object_id` explicitly. This is a role, not
  ownership.
- The Entra app registration, service principal and group are owned by the person
  running bootstrap. That's required: with the Application Developer role you can
  only manage apps you own. Add a colleague with `additional_owners` so you aren't
  the only one.
- Give people workspace access through an **Entra group** via
  `additional_role_assignments` (see `fabric/terraform.tfvars.example`).

## Case-insensitive collation (DataEngineering only)

Only the DataEngineering workspaces hold SQL artifacts. All of them are created
case insensitive (`Latin1_General_100_CI_AS_KS_WS_SC_UTF8`):

- **Warehouses** get the collation set explicitly at creation.
- **The lakehouse SQL endpoint** always takes the workspace's *Data Warehouse
  collation* setting, which Fabric only exposes in the portal (no API). So
  `fabric/` runs in two passes:
  1. First `apply` creates the workspaces and warehouses, and **skips the
     lakehouse** (you'll see a warning).
  2. In **DataEngineeringDev** and **DataEngineeringProd**: **Workspace settings →
     Data Warehouse → Collations → Case insensitive**.
  3. Set `workspace_collation_confirmed = true` in `fabric/terraform.tfvars` and
     `apply` again to create `LH_Bronze`.
- Collation can never be changed after an item is created.
- To change the setting you need Admin/Member/Contributor on the workspace - add
  your admin group through `additional_role_assignments` before step 2.

## 1. Bootstrap (as yourself)

You need: **Owner** on the subscription and **Application Developer** (or higher)
in Entra. Creating the security group also requires that users may create
security groups in your tenant (the Entra default).

```powershell
az login
cd infra/capacities/bootstrap
terraform init
terraform apply      # prompts for subscription, company code, region, version
```

To skip the prompts next time, copy `terraform.tfvars.example` to
`terraform.tfvars` and fill it in.

**Client secret:** valid for 730 days (the Entra portal maximum) and stored in the
Key Vault as `executor-client-secret`, next to `executor-client-id` and
`executor-tenant-id`. The vault uses Azure RBAC, purge protection and 90-day soft
delete; you get *Key Vault Secrets Officer* on it. Running bootstrap again after
the secret expires creates a new one and updates the vault.

**Fabric tenant settings** are not changed by these scripts. As Fabric
administrator, add the group `cg-we-dp-01-da-sg-terraform-executors` (name from
the bootstrap output) in the Fabric admin portal → Tenant settings → Developer
settings to:
- *Service principals can create workspaces, connections, and deployment pipelines*
- *Service principals can call Fabric public APIs*

Leave a setting alone if it's already enabled for the entire organization.

## 2. and 3. Running as the executor

Load the credentials from Key Vault into the current terminal (never into files),
with the leading dot:

```powershell
. ./infra/Load-Credentials.ps1 -GitProvider GitHub     # or AzureDevOps
```

Capacities (they cost money while running - pause them when idle):

```powershell
cd infra/capacities
terraform init
terraform apply
```

Fabric:

```powershell
cd infra/fabric
terraform init
terraform apply
```

To use an existing capacity instead, set `capacity_name_overrides` in
`fabric/terraform.tfvars` and skip step 2. Capacities must be **running**, and the
executor must be a capacity admin or contributor.

GitHub Actions uses OIDC instead of the secret: set `ARM_USE_OIDC=true` /
`FABRIC_USE_OIDC=true` with the tenant and client IDs. The trust is set up for
`main` and pull requests on `COLAndreasOlling/fabric-data-platform`.

## State

State is local (`terraform.tfstate`, git-ignored) for now. The bootstrap state
also contains the client secret - never commit or share it. Before running from
GitHub Actions or sharing with colleagues, move state to an Azure Storage backend.

## Known limits

- Workspace **Viewer** on DataEngineering lets the ReportingHub identity read all
  items there (including `LH_Bronze` through its SQL endpoint). The Fabric
  provider doesn't support item-level permissions yet; tighten later by sharing
  only `WH_Gold_DataEstate` or using OneLake data access roles.
- Lakehouse schemas and collations can't be changed after creation.
- Changing the company code, region or version renames everything, which means
  Terraform replaces the resources - treat them as fixed once deployed.
