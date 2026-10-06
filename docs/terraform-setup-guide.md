# Terraform setup guide

Step-by-step instructions for deploying the Fabric data platform from scratch.
Every command is PowerShell, run from the repository root unless a step says
otherwise. Follow the steps in order — each one tells you what to expect, so you
can stop as soon as something looks different.

**Already have an Azure/Fabric environment** with a service principal, Key Vault or
capacities? Read [Using an existing environment](#using-an-existing-environment)
first — you can skip parts of this guide.

| Step | What happens | Signed in as | Time |
|---|---|---|---|
| 0 | Check tools, roles and the customer's Git repository; collect your answers | You | 15 min |
| 1 | Bootstrap: service principal, resource groups, Key Vault | You | 5 min |
| 2 | Fabric tenant settings (manual) | You, Fabric admin | 5 min |
| 3 | Give the platform access to the Git repository | You | 5 min |
| 4 | Load the credentials | You | 1 min |
| 5 | Capacities | Service principal | 5 min |
| 6 | Workspaces, warehouses and Git connection (pass 1) | Service principal | 5 min |
| 7 | Case-insensitive collation (manual) | You | 2 min |
| 8 | Lakehouse (pass 2) | Service principal | 2 min |
| 9 | Verify and make the first Git commit | You | 10 min |

---

## Step 0 — Before you start

### 0.1 Tools

```powershell
terraform version   # 1.10 or newer
az version          # Azure CLI
git --version
```

### 0.2 Roles you need

| Where | Role | Used for |
|---|---|---|
| Azure subscription | **Owner** | Resource groups, role assignments, Key Vault |
| Entra ID | **Application Developer** (or higher) | Creating the app registration |
| Entra ID | Allowed to create security groups (default) | Executor group |
| Fabric | **Fabric Administrator** | Tenant settings in step 2 |
| Git (customer's) | Admin on the repository / Azure DevOps project | Step 3 |

### 0.3 The customer's Git repository — must exist before you start

Terraform **connects** the Dev workspaces to Git; it does **not** create the
repository or the branch. It **does** create the workspace folders if they're
missing (Fabric refuses to connect to a folder that doesn't exist): one commit
with a `README.md` per folder, made by the service principal (Azure DevOps) or
the token's account (GitHub). If `main` has a branch policy / protection that
blocks direct commits, create the folders yourself first. Confirm with the customer:

**GitHub**
- [ ] A repository exists, e.g. `https://github.com/<owner>/<repo>`.
- [ ] The branch you'll use (e.g. `main`) exists — the repository has at least one commit.
- [ ] Someone can create a **personal access token** for it (step 3). Commits from
      Fabric are made as that token's GitHub account, so a shared/service account is
      better than a person's.
- [ ] If it's in a GitHub organization: fine-grained tokens are allowed (or use a classic token).

**Azure DevOps**
- [ ] An organization and project with a repository, e.g.
      `https://dev.azure.com/<organization>/<project>/_git/<repo>`.
- [ ] The branch you'll use (e.g. `main`) exists — the repository has at least one commit.
- [ ] The Azure DevOps organization is **connected to the same Entra tenant** as
      Fabric (Organization settings → Microsoft Entra).
- [ ] Someone who is Project Collection Administrator can add a service principal (step 3).

### 0.4 Collect your answers

Write these down. Terraform asks for each one — the same answers every time —
so it's easiest to put them in `terraform.tfvars` files as you go.

| Asked in | Question | Example | Notes |
|---|---|---|---|
| Step 1 | `subscription_id` | `1a2b3c4d-…` | Where everything is deployed |
| Step 1 | `company_code` | `cg` | Becomes `p-cg-we-dp-01-da` |
| Step 1 | `location` | `westeurope` | `we` in names; the Azure region |
| Step 1 | `platform_version` | `01` | `…-dp-01-…` |
| Step 1 | `alert_email_addresses` | `dataplatform@customer.com, you@columbusglobal.com` | Warned 90 days, 30 days and on the day before the service principal's secret or the GitHub token expires. Use a shared mailbox that someone reads |
| Step 6 | `git_provider` | `GitHub` or `AzureDevOps` | Exactly as written |
| Step 6 | `git_repository_url` | `https://github.com/contoso/fabric` | Copy from the browser / Clone button |
| Step 6 | `git_branch` | `main` | Must already exist |
| Step 6 | `git_folder` | `/fabric` | Each workspace gets a subfolder: `/fabric/DataEngineering`, `/fabric/ReportingHub`, `/fabric/ReportingInsights`. Use `/` for the repository root |

The naming inputs **can't be changed later** without recreating everything. Key
Vault names are **globally unique** in Azure; if `p-<company>-<region>-dp-01-da-kv`
is taken, use another `platform_version` (e.g. `02`).

---

## Step 1 — Bootstrap

### 1.1 Sign in as yourself

```powershell
az login --tenant <customer-tenant-id-or-domain>
```

If the sign-in window picks the wrong account, use
`az login --tenant <tenant> --use-device-code` and open the link in a private
browser window.

```powershell
az account set --subscription <subscription-id>
az account show --query "{tenant:tenantId, subscription:name, user:user.name}" -o table
```

Check that the tenant, subscription and user are the ones you expect.

### 1.2 Make sure no service principal variables are set

Bootstrap must run as **you**. In a terminal where you ran step 4 before, clear them:

```powershell
Remove-Item Env:ARM_*, Env:FABRIC_*, Env:TF_VAR_git_secret -ErrorAction SilentlyContinue
```

### 1.3 Run bootstrap

```powershell
cd infra/capacities/bootstrap
Copy-Item terraform.tfvars.example terraform.tfvars
notepad terraform.tfvars        # fill in the five step-1 values from 0.4, remove the #
terraform init
terraform plan
```

(Without `terraform.tfvars`, Terraform asks for the five values instead.)

Read the plan — you should see **22 resources to add**: an application, service
principal, two federated credentials, a password, a group, two resource groups,
three role assignments, a Key Vault, four secrets (one is the renewal reminder),
an action group, an Event Grid system topic and its alert subscription, a wait
timer, a rotation timer and `platform.json`. Nothing should be changed or destroyed.

```powershell
terraform apply
```

Type `yes`. It takes a few minutes (including a 90 second wait for Key Vault
permissions).

### 1.4 Check the result

```powershell
terraform output
```

You'll see the generated names, the service principal's client ID, the Key Vault
name and `expiry_warnings`: who's warned, when the secret expires and the date of
the first warning. Each address in the action group gets a confirmation email
from Azure Monitor ("You've been added to an action group") — that's how you know
the addresses are right.

In the **Entra admin center → App registrations → `<company>-<region>-dp-<version>-da-sp-terraform`**:
- *Owners*: you (and anyone in `additional_owners`).
- *Certificates & secrets*: one client secret and two federated credentials.

In the **Azure portal → Key Vault `p-…-kv` → Secrets**: `executor-client-id`,
`executor-client-secret`, `executor-tenant-id`.

### 1.5 Commit `platform.json`

Bootstrap wrote `infra/platform.json` (names and IDs only, no secrets). The other
steps read it, so commit it:

```powershell
cd ../../..          # back to the repository root
git add infra/platform.json
git commit -m "Add platform settings from bootstrap"
git push
```

> The bootstrap state file (`infra/capacities/bootstrap/terraform.tfstate`)
> **contains the client secret**. It's git-ignored — never commit, email or share it.

---

## Step 2 — Fabric tenant settings (manual)

The scripts don't change tenant settings. As Fabric administrator, open
**app.fabric.microsoft.com → Settings (gear) → Admin portal → Tenant settings**
and check each setting below:

| Setting | Needed for |
|---|---|
| *Service principals can create workspaces, connections, and deployment pipelines* | Workspaces and the Git connection |
| *Service principals can call Fabric public APIs* | Everything the service principal does |
| *Users can synchronize workspace items with their Git repositories* | Git integration |
| *Users can sync workspace items with GitHub repositories* | Only if the repository is on GitHub |

For each one:
- **Enabled for the entire organization**: leave it.
- **Enabled for specific security groups**: add the group
  `<company>-<region>-dp-<version>-da-sg-terraform-executors`. Don't remove existing groups.
- **Disabled**: enable it for *Specific security groups* and add only that group.

Click **Apply** on each. Changes can take up to 15 minutes.

---

## Step 3 — Give the platform access to the Git repository

### GitHub: create a token and store it in Key Vault

1. Sign in to GitHub with the account Fabric should commit as.
2. **Settings → Developer settings → Personal access tokens → Fine-grained tokens →
   Generate new token.**
   - *Resource owner*: the repository's owner.
   - *Repository access*: **Only select repositories** → the repository.
   - *Permissions → Repository → Contents*: **Read and write**.
   - *Expiration*: as long as the organization allows; note the date.
3. Copy the token, then store it — it asks for the token (hidden) and the expiry date:

```powershell
./infra/Save-GitToken.ps1
```

You'll see `Saved as secret 'git-token' in Key Vault '…'`.

### Azure DevOps: add the service principal to the organization

1. In Azure DevOps: **Organization settings → Users → Add users**.
2. Search for the service principal `<company>-<region>-dp-<version>-da-sp-terraform`
   and set the access level to **Basic**. *Stakeholder* (free) is not enough:
   Stakeholders can't read or write code in Repos, so Fabric can't sync.
3. In the same dialog, add it to the **project** in the **Contributors** group.
   The licence only lets it into Repos; Contributors gives it permission to push.
4. Check: **Project settings → Repositories → <repo> → Security** — the service
   principal (through Contributors) has **Read** and **Contribute** = Allow.

No token is needed: Fabric connects as the service principal.

---

## Step 4 — Load the credentials

Steps 5–8 run as the service principal. This loads its credentials (and the Git
secret) from Key Vault into the **current terminal only**. Note the leading dot:

```powershell
. ./infra/Load-Credentials.ps1 -GitProvider GitHub        # or AzureDevOps
```

It checks that you're signed in to the right tenant as yourself, and shows:

```
Credentials loaded for this PowerShell session:
  Orchestrator (you)  : you@customer.com
  Tenant              : …
  Service principal   : …
  Key Vault           : p-…-kv
  Git provider        : GitHub (token from secret 'git-token')
```

If you open a new terminal, run it again.

---

## Step 5 — Capacities

> Capacities are **billed per hour while running**. Only do this step when
> you're ready to pay for them, and pause them when idle (step 9.4).

```powershell
cd infra/capacities
terraform init
terraform plan
```

You should see **2 to add**: `dcg…fab` and `pcg…fab`, both F2. To change sizes,
copy `terraform.tfvars.example` to `terraform.tfvars` and set `capacity_skus`.

```powershell
terraform apply
cd ../..
```

---

## Step 6 — Workspaces, warehouses and Git (pass 1)

Put your Git answers from 0.4 in `infra/fabric/terraform.tfvars`:

```powershell
cd infra/fabric
Copy-Item terraform.tfvars.example terraform.tfvars
notepad terraform.tfvars
```

```hcl
git_provider       = "GitHub"                              # or "AzureDevOps"
git_repository_url = "https://github.com/<owner>/<repo>"   # or https://dev.azure.com/<org>/<project>/_git/<repo>
git_branch         = "main"
git_folder         = "/fabric"
```

(Without these lines, Terraform asks for them. A URL that doesn't match the
provider is rejected with an explanation.)

```powershell
terraform init
terraform plan
```

Check the plan:
- The first lines show `orchestrator = "<your UPN>"` — that's you, made Admin on every workspace.
- A **warning** about *'Folder' preview mode*. That's expected.
- **Add**: 6 workspaces, 8 folders (`100_Bronze` … `400_DataTransformation` in
  both DataEngineering workspaces), 6 warehouses, 10 role assignments (4 cross-workspace,
  6 for you), 1 Git connection, 1 connection role assignment,
  `terraform_data.git_folders` (creates missing folders in the repository) and
  3 workspace Git connections (the Dev workspaces).
- A **warning** that lakehouses are skipped. That's expected.
- Nothing to change or destroy.

```powershell
terraform apply
```

---

## Step 7 — Case-insensitive collation (manual)

The lakehouse SQL endpoint copies the workspace collation when it's created, and
Fabric only lets you set that in the portal. You're Admin on every workspace
(step 6), so you can change it.

For **DataEngineeringDev** and **DataEngineeringProd**:

1. Open the workspace in Fabric → **Workspace settings**.
2. **Data Warehouse → Collations**.
3. Choose **Case insensitive (Latin1_General_100_CI_AS_KS_WS_SC_UTF8)** and save.

To give colleagues access as well, add a group to `infra/fabric/terraform.tfvars`
(and apply in step 8):

```hcl
additional_role_assignments = [
  { workspace_type = "DataEngineering",   principal_id = "<group-object-id>", principal_type = "Group", role = "Admin" },
  { workspace_type = "ReportingHub",      principal_id = "<group-object-id>", principal_type = "Group", role = "Admin" },
  { workspace_type = "ReportingInsights", principal_id = "<group-object-id>", principal_type = "Group", role = "Admin" },
]
```

---

## Step 8 — Lakehouse (pass 2)

Add this line to `infra/fabric/terraform.tfvars`:

```hcl
workspace_collation_confirmed = true
```

```powershell
terraform plan     # expect 2 lakehouses to add, no warning
terraform apply
cd ../..
```

---

## Step 9 — Verify

### 9.1 Workspaces and access

- Six workspaces exist, each on the right capacity (Workspace settings → License info).
- **DataEngineering** workspaces contain the folders `100_Bronze` (`LH_Bronze`),
  `200_Silver` (`WH_Silver_Sources`, `WH_Silver_Models`), `300_Gold`
  (`WH_Gold_DataEstate`) and an empty `400_DataTransformation`.
- **Manage access** on DataEngineeringDev shows the service principal (Admin),
  you (Admin), any groups you added and `ReportingHubDev`'s workspace identity
  (Viewer).

### 9.2 Collation

Open each warehouse and the `LH_Bronze` SQL analytics endpoint, run:

```sql
SELECT name, collation_name FROM sys.databases;
```

Every row should say `Latin1_General_100_CI_AS_KS_WS_SC_UTF8`.

### 9.3 Git — make the first commit

```powershell
terraform -chdir=infra/fabric output git
```

shows the repository, branch and a folder per Dev workspace. Then, in each Dev workspace:

1. **Source control** (top bar) shows the branch and the items that aren't in Git
   yet (e.g. the warehouses and lakehouse in DataEngineeringDev).
2. Select all → **Commit** with a message like "Initial commit".
3. The items now appear in the repository under `/fabric/DataEngineering` etc.

If Source control asks for credentials, choose the connection
`git-<owner>-<repo>` (you have access to it).

### 9.4 Pause capacities when idle

```powershell
$p = Get-Content infra/platform.json | ConvertFrom-Json
foreach ($e in $p.environments.PSObject.Properties.Value) {
  az fabric capacity suspend --resource-group $e.resource_group --capacity-name $e.capacity_name
}
```

(Resume with `az fabric capacity resume …`. The `az fabric` commands need the
extension: `az extension add --name microsoft-fabric`. You can also pause in the
Azure portal.) Terraform needs the capacities **running** to deploy.

---

## Day-to-day changes

1. Load credentials (step 4).
2. Edit `.tf` / `terraform.tfvars`.
3. `terraform plan` — read it carefully. **Any line saying `must be replaced` or
   `destroy` on a lakehouse, warehouse or workspace deletes its data.** Changing
   the Git repository, branch or folder replaces the workspace's Git connection
   (no data loss, but uncommitted changes are lost).
4. `terraform apply`.
5. Commit the `.tf` changes (never state or `terraform.tfvars`).

## Expiring credentials and warnings

The service principal itself doesn't expire — its **client secret** does (730
days), and so does the **GitHub token** (whatever was set on GitHub).

### What stops working when they expire

| Expired | Stops | Keeps working |
|---|---|---|
| Executor client secret | Terraform runs (can't sign in). With **Azure DevOps**: the workspaces' Git connection, so Source control can't commit or update. | Workspaces, lakehouse, warehouses and the data in them. Items owned by the service principal (e.g. scheduled pipelines) are run by Fabric under the service principal's identity without using its secret — verify this for your item types before relying on it. A **deleted or disabled** service principal does break them, so never delete it. |
| GitHub token | The workspaces' Git connection (GitHub) | Everything else |

### How you're warned

Key Vault raises an event 30 days before a secret expires and on the expiry day;
Event Grid turns these into Azure Monitor alerts emailed to `alert_email_addresses`.
For an earlier warning, each credential has a *renewal reminder* secret that
expires earlier, giving a first email `expiry_warning_days` (default **90**) days ahead:

| When | Email about |
|---|---|
| 90 days before | `executor-client-secret-renewal-reminder` / `git-token-renewal-reminder` is "near expiry" — time to plan the renewal |
| 30 days before | `executor-client-secret` / `git-token` is near expiry |
| On the day | It has expired |

The alerts are also visible in the Azure portal under **Monitor → Alerts**.
Change the recipients in `infra/capacities/bootstrap/terraform.tfvars` and run
bootstrap again.

> Key Vault only raises these events for secrets written *after* the alert
> subscription exists. Bootstrap takes care of the order; if you add secrets to
> the vault by hand, add them afterwards (or write a new version).

### Renewing

- **Executor client secret**: run step 1.3 again as yourself — after the rotation
  date it creates a new secret and updates Key Vault and the reminder. To renew
  **early** (e.g. after the 90-day warning), force it:
  `terraform apply -replace="time_rotating.client_secret"`. For Azure DevOps, then
  increase `git_secret_version` in `infra/fabric/terraform.tfvars`, load the
  credentials (step 4) and apply `infra/fabric`, so the Git connection gets the
  new secret.
- **GitHub token**: create a new one, run `./infra/Save-GitToken.ps1` (it also
  updates the reminder), increase `git_secret_version` and apply `infra/fabric`.

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `403 Forbidden` writing a Key Vault secret | Your Key Vault role hasn't taken effect yet | Wait a minute, run `terraform apply` again |
| `PrincipalNotFound` on a role assignment | The new service principal hasn't replicated yet | Run `terraform apply` again |
| `VaultAlreadyExists` / name not available | Key Vault name taken globally, or a deleted vault with that name is still soft-deleted | Use another `platform_version`, or recover the deleted vault |
| `Authorization_RequestDenied` creating the group | Users can't create security groups in your tenant | Ask an Entra admin for Groups Administrator, or to create the group |
| `401 Unauthorized` / `403 Forbidden` from the Fabric API | Tenant settings (step 2) missing or not applied yet | Check step 2; wait 15 minutes |
| `Capacity … is not active` | Capacity paused | Resume it (step 9.4) |
| `WorkspaceNameAlreadyExists` | A workspace with that name already exists in the tenant | Set `workspace_name_prefix` in `infra/fabric/terraform.tfvars` |
| `Error: building client: … use_cli` / no credentials | Step 4 not run in this terminal | Run step 4 |
| Terraform asks for `git_secret` | Step 4 not run, or run with the wrong `-GitProvider` | Run step 4; don't type the secret at the prompt |
| `The URL doesn't match git_provider` | Provider and URL disagree, or the URL has extra parts | Copy the plain repository URL (see 0.4) |
| Git connection fails: credentials / unauthorized | GitHub: token expired or lacks Contents read/write on that repository. Azure DevOps: service principal not in the organization/project, or the organization is in another tenant | Step 3 |
| Git connect fails: branch not found | The branch doesn't exist (empty repository) | Create the branch / make a first commit in the repository |
| `GitProviderResourceNotFound` | The workspace folder doesn't exist in the repository | Normally created by `terraform_data.git_folders`; if that was skipped, create the folders (e.g. with a README.md) and apply again |
| `couldn't commit the folders` / `couldn't create … (HTTP 403/409)` | Branch policy or protection blocks direct commits, or no write access | Create the folders yourself through a pull request, then apply again — existing folders are left alone |
| `Couldn't read secret … from Key Vault` | Wrong vault or secret name, or no access | Pass `-KeyVaultName` / `-ClientSecretName`; you need *Key Vault Secrets User* |
| Bootstrap prompts for the service principal | ARM_/FABRIC_ variables still set | Step 1.2 |

## Removing everything

Reverse order, each with the right identity. **This deletes all data.**

```powershell
# As the service principal (step 4 loaded):
cd infra/fabric;      terraform destroy; cd ../..
cd infra/capacities;  terraform destroy; cd ../..

# As yourself (clear the variables first, step 1.2):
cd infra/capacities/bootstrap; terraform destroy; cd ../../..
```

Destroying `infra/fabric` disconnects the workspaces from Git; the repository and
its content are left untouched. The Key Vault is soft-deleted with purge
protection: its name stays reserved for 90 days.

---

## Using an existing environment

The three configurations are independent: each reads `infra/platform.json` and
creates only its own part. So you can skip whatever your environment already has.

| You already have | Do this |
|---|---|
| Fabric capacities | Skip step 5. Set `capacity_name_overrides = { Dev = "<name>", Prod = "<name>" }` in `infra/fabric/terraform.tfvars`. The service principal must be **capacity admin or contributor** on them. |
| A service principal for deployments, Key Vault and resource groups | Skip step 1. Copy `infra/platform.example.json` to `infra/platform.json` and fill in your values (`tenant_id`, `executor_client_id`, `key_vault_name`, capacity names). In step 4 pass your secret's name: `. ./infra/Load-Credentials.ps1 -GitProvider … -ClientSecretName <name>`. |
| Only some of it (e.g. a Key Vault but no service principal) | Bootstrap creates everything in one go, so either run it and accept a new vault/resource groups, or import your existing resources (below). |
| Only want workspaces and items | Do steps 2, 3, 4, 6–9 with an existing service principal and existing capacities. |
| Only Dev (no Prod yet) | List only `Dev` under `environments` in `platform.json`. Prod can be added later without touching Dev. |

What the `fabric/` part needs from your environment, however it was set up:
- A service principal (not a user) with its secret in a Key Vault you can read.
- That service principal in the tenant settings from step 2.
- Running capacities where the service principal is admin or contributor.
- Free workspace names (or a `workspace_name_prefix`).
- The Git repository and branch from 0.3, with access from step 3.

### Adopting existing resources

If something already exists with exactly the name Terraform would create (a
resource group, a Key Vault), Terraform fails with *already exists*. You can tell
Terraform to manage the existing one instead of creating it, with an `import`
block, e.g. in `infra/capacities/bootstrap/imports.tf`:

```hcl
import {
  to = azurerm_resource_group.this["Prod"]
  id = "/subscriptions/<subscription-id>/resourceGroups/p-cg-we-dp-01-da"
}
```

`terraform plan` then shows the resource as *imported* (and any settings
Terraform would change on it). Read that plan carefully: Terraform will make the
existing resource match the code — e.g. tags, or purge protection on a Key Vault.
