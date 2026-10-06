# Terraform setup guide

Step-by-step instructions for deploying the Fabric data platform from scratch.
Every command is PowerShell, run from the repository root
(`C:\Repos\Github\fabric-data-platform`) unless a step says otherwise.

**Already have an Azure/Fabric environment** with a service principal, Key Vault or
capacities? Read [Using an existing environment](#using-an-existing-environment)
first — you can skip parts of this guide.

| Step | What happens | Signed in as | Time |
|---|---|---|---|
| 0 | Check tools and roles | You | 5 min |
| 1 | Bootstrap: service principal, resource groups, Key Vault | You | 5 min |
| 2 | Fabric tenant settings (manual) | You, Fabric admin | 5 min |
| 3 | Load the service principal's credentials | — | 1 min |
| 4 | Capacities | Service principal | 5 min |
| 5 | Workspaces and warehouses (pass 1) | Service principal | 5 min |
| 6 | Case-insensitive collation (manual) | You | 2 min |
| 7 | Lakehouse (pass 2) | Service principal | 2 min |
| 8 | Verify | You | 5 min |

---

## Step 0 — Check tools and roles

### Tools

```powershell
terraform version   # 1.8 or newer
az version          # Azure CLI
git --version
```

### Roles you need

| Where | Role | Used for |
|---|---|---|
| Azure subscription | **Owner** | Resource groups, role assignments, Key Vault |
| Entra ID | **Application Developer** (or higher) | Creating the app registration |
| Entra ID | Allowed to create security groups (default) | Executor group |
| Fabric | **Fabric Administrator** | Tenant settings in step 2 |

### Decide your naming inputs

You'll be prompted for these in step 1. Write them down — they become part of
every resource name and **can't be changed later** without recreating everything.

| Prompt | Example | Becomes |
|---|---|---|
| `subscription_id` | `1a2b3c4d-…` | Where everything is deployed |
| `company_code` | `cg` | `p-cg-we-dp-01-da` |
| `location` | `westeurope` | `we` in names; the Azure region |
| `platform_version` | `01` | `…-dp-01-…` |

Key Vault names are **globally unique** in Azure. If `p-<company>-<region>-dp-01-da-kv`
is taken, use another `platform_version` (e.g. `02`).

---

## Step 1 — Bootstrap

### 1.1 Sign in as yourself

```powershell
az login --tenant <your-tenant-id-or-domain>
az account set --subscription <subscription-id>
az account show --query "{subscription:name, user:user.name}" -o table
```

Check that the subscription and user are the ones you expect.

### 1.2 Make sure no service principal variables are set

Bootstrap must run as **you**. If you ran step 3 earlier in this terminal, clear them:

```powershell
Remove-Item Env:ARM_*, Env:FABRIC_* -ErrorAction SilentlyContinue
```

### 1.3 Run bootstrap

```powershell
cd infra/capacities/bootstrap
terraform init
terraform plan
```

Answer the four prompts. Read the plan — you should see **19 resources to add**: an
application, service principal, two federated credentials, a password, a group,
two resource groups, three role assignments, a Key Vault, three secrets, a wait
timer, a rotation timer and `platform.json`. Nothing should be changed or
destroyed.

```powershell
terraform apply
```

Answer the prompts again and type `yes`. It takes a few minutes (including a 90
second wait for Key Vault permissions).

> **Tip:** to avoid answering the prompts every time, copy
> `terraform.tfvars.example` to `terraform.tfvars` and fill it in. That file is
> git-ignored.

### 1.4 Check the result

```powershell
terraform output
```

You'll see the generated names, the service principal's client ID, the secret's
expiry date and the Key Vault name.

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

The scripts don't change tenant settings. As Fabric administrator:

1. Open **app.fabric.microsoft.com → Settings (gear) → Admin portal → Tenant settings**.
2. Search for **Service principals can create workspaces, connections, and deployment pipelines**.
   - If it's **enabled for the entire organization**: leave it.
   - If it's **enabled for specific security groups**: add `<company>-<region>-dp-<version>-da-sg-terraform-executors`
     to the list. Don't remove existing groups.
   - If it's **disabled**: enable it for *Specific security groups* and add only that group.
3. Repeat for **Service principals can call Fabric public APIs**.
4. Click **Apply** on each. Changes can take up to 15 minutes.

---

## Step 3 — Load the service principal's credentials

Steps 4–7 run as the service principal. Load its credentials from Key Vault into
the **current terminal only** (you stay signed in to `az` as yourself; that's
just to read the vault):

```powershell
$kv = (Get-Content infra/platform.json | ConvertFrom-Json).key_vault_name

$env:ARM_TENANT_ID     = az keyvault secret show --vault-name $kv --name executor-tenant-id     --query value -o tsv
$env:ARM_CLIENT_ID     = az keyvault secret show --vault-name $kv --name executor-client-id     --query value -o tsv
$env:ARM_CLIENT_SECRET = az keyvault secret show --vault-name $kv --name executor-client-secret --query value -o tsv

$env:FABRIC_TENANT_ID     = $env:ARM_TENANT_ID
$env:FABRIC_CLIENT_ID     = $env:ARM_CLIENT_ID
$env:FABRIC_CLIENT_SECRET = $env:ARM_CLIENT_SECRET
```

Check they're set (without printing the secret):

```powershell
"Client ID: $env:ARM_CLIENT_ID  Secret loaded: $([bool]$env:ARM_CLIENT_SECRET)"
```

If you open a new terminal, repeat this step.

---

## Step 4 — Capacities

> Capacities are **billed per hour while running**. Only do this step when
> you're ready to pay for them, and pause them when idle (step 8.3).

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

## Step 5 — Workspaces and warehouses (pass 1)

```powershell
cd infra/fabric
terraform init
terraform plan
```

Expect **6 workspaces, 6 warehouses and 4 role assignments** (the workspace
identities' cross-workspace access, Dev and Prod) to add, plus a
**warning** that lakehouses are skipped. That warning is expected.

```powershell
terraform apply
```

---

## Step 6 — Case-insensitive collation (manual)

The lakehouse SQL endpoint copies the workspace collation when it's created, and
Fabric only lets you set that in the portal.

To change the setting you need a role on the workspace. The service principal is
the only Admin so far, so first give your admin group access. Find the group's
object ID in Entra, then create `infra/fabric/terraform.tfvars`:

```hcl
additional_role_assignments = [
  { workspace_type = "DataEngineering",   principal_id = "<group-object-id>", principal_type = "Group", role = "Admin" },
  { workspace_type = "ReportingHub",      principal_id = "<group-object-id>", principal_type = "Group", role = "Admin" },
  { workspace_type = "ReportingInsights", principal_id = "<group-object-id>", principal_type = "Group", role = "Admin" },
]
```

```powershell
terraform apply
```

Then, for **DataEngineeringDev** and **DataEngineeringProd**:

1. Open the workspace in Fabric → **Workspace settings**.
2. **Data Warehouse → Collations**.
3. Choose **Case insensitive (Latin1_General_100_CI_AS_KS_WS_SC_UTF8)** and save.

---

## Step 7 — Lakehouse (pass 2)

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

## Step 8 — Verify

### 8.1 In Fabric

- Six workspaces exist, each on the right capacity (Workspace settings → License info).
- **DataEngineering** workspaces contain `LH_Bronze`, `WH_Silver_Sources`,
  `WH_Silver_Models`, `WH_Gold_DataEstate`.
- **Manage access** on DataEngineeringDev shows the service principal (Admin),
  your group (Admin) and `ReportingHubDev`'s workspace identity (Viewer).

### 8.2 Collation

Open each warehouse and the `LH_Bronze` SQL analytics endpoint, run:

```sql
SELECT name, collation_name FROM sys.databases;
```

Every row should say `Latin1_General_100_CI_AS_KS_WS_SC_UTF8`.

### 8.3 Pause capacities when idle

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

1. Load credentials (step 3).
2. Edit `.tf` / `terraform.tfvars`.
3. `terraform plan` — read it carefully. **Any line saying `must be replaced` or
   `destroy` on a lakehouse or warehouse deletes its data.**
4. `terraform apply`.
5. Commit the `.tf` changes (never state or `terraform.tfvars`).

## Rotating the client secret

The secret is valid for 730 days. Before it expires, run step 1.3 again (as
yourself) — after the rotation date it creates a new secret and updates Key Vault.
Check the expiry with `terraform output` in `infra/capacities/bootstrap`.

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `403 Forbidden` writing a Key Vault secret | Your Key Vault role hasn't taken effect yet | Wait a minute, run `terraform apply` again |
| `PrincipalNotFound` on a role assignment | The new service principal hasn't replicated yet | Run `terraform apply` again |
| `VaultAlreadyExists` / name not available | Key Vault name taken globally, or a deleted vault with that name is still soft-deleted | Use another `platform_version`, or recover the deleted vault |
| `Authorization_RequestDenied` creating the group | Users can't create security groups in your tenant | Ask an Entra admin for Groups Administrator, or to create the group |
| `401 Unauthorized` / `403 Forbidden` from the Fabric API | Tenant settings (step 2) missing or not applied yet | Check step 2; wait 15 minutes |
| `Capacity … is not active` | Capacity paused | Resume it (step 8.3) |
| `WorkspaceNameAlreadyExists` | A workspace with that name already exists in the tenant | Set `workspace_name_prefix` in `infra/fabric/terraform.tfvars` |
| `Error: building client: … use_cli` / no credentials | Step 3 not run in this terminal | Run step 3 |
| Bootstrap prompts for the service principal | ARM_/FABRIC_ variables still set | Step 1.2 |

## Removing everything

Reverse order, each with the right identity. **This deletes all data.**

```powershell
# As the service principal (step 3 loaded):
cd infra/fabric;      terraform destroy; cd ../..
cd infra/capacities;  terraform destroy; cd ../..

# As yourself (clear ARM_/FABRIC_ variables first, step 1.2):
cd infra/capacities/bootstrap; terraform destroy; cd ../../..
```

The Key Vault is soft-deleted with purge protection: its name stays reserved for
90 days.

---

## Using an existing environment

The three configurations are independent: each reads `infra/platform.json` and
creates only its own part. So you can skip whatever your environment already has.

| You already have | Do this |
|---|---|
| Fabric capacities | Skip step 4. Set `capacity_name_overrides = { Dev = "<name>", Prod = "<name>" }` in `infra/fabric/terraform.tfvars`. The service principal must be **capacity admin or contributor** on them. |
| A service principal for deployments, Key Vault and resource groups | Skip step 1. Copy `infra/platform.example.json` to `infra/platform.json` and fill in your values (`executor_client_id`, `key_vault_name`, resource groups). Load its credentials yourself in step 3 (from your vault, with your secret names). |
| Only some of it (e.g. a Key Vault but no service principal) | Bootstrap creates everything in one go, so either run it and accept a new vault/resource groups, or import your existing resources (below). |
| Only want workspaces and items | Do steps 2, 3, 5–8 with an existing service principal and existing capacities. |

What the `fabric/` part needs from your environment, however it was set up:
- A service principal (not a user) with credentials you can load in step 3.
- That service principal in the tenant settings from step 2.
- Running capacities where the service principal is admin or contributor.
- Free workspace names (or a `workspace_name_prefix`).

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
