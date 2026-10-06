# Environments and capacity names come from ../platform.json (written by
# ../capacities/bootstrap). Override a capacity here to use an existing one.
variable "capacity_name_overrides" {
  description = "Use an existing Fabric capacity for an environment, e.g. { Dev = \"mytrialcapacity\" }."
  type        = map(string)
  default     = {}
}

# --- Git integration -------------------------------------------------------------
# No defaults on purpose: Terraform asks for these unless they're in
# terraform.tfvars. The repository and branch must already exist.

variable "git_provider" {
  description = "Where the customer's existing repository is: GitHub or AzureDevOps."
  type        = string

  validation {
    condition     = contains(["GitHub", "AzureDevOps"], var.git_provider)
    error_message = "git_provider must be exactly GitHub or AzureDevOps."
  }
}

variable "git_repository_url" {
  description = "Full URL of the existing repository. GitHub: https://github.com/<owner>/<repo>  Azure DevOps: https://dev.azure.com/<organization>/<project>/_git/<repo>"
  type        = string

  validation {
    condition = (
      var.git_provider == "GitHub"
      ? can(regex("^https://github\\.com/[^/]+/[^/]+?(\\.git)?/?$", var.git_repository_url))
      : can(regex("^https://(?:[^@/]+@)?dev\\.azure\\.com/[^/]+/[^/]+/_git/[^/?#]+/?$", var.git_repository_url))
    )
    error_message = "The URL doesn't match git_provider. GitHub: https://github.com/<owner>/<repo>. Azure DevOps: https://dev.azure.com/<organization>/<project>/_git/<repo> (copy it from Repos > Clone, without trailing paths)."
  }
}

variable "git_branch" {
  description = "Existing branch the workspaces sync with, e.g. main. It must already exist in the repository."
  type        = string

  validation {
    condition     = length(trimspace(var.git_branch)) > 0 && !can(regex("\\s", var.git_branch))
    error_message = "git_branch must be a branch name without spaces, e.g. main."
  }
}

variable "git_folder" {
  description = "Folder in the repository for Fabric items, starting with /, e.g. /fabric. Each workspace gets a subfolder: /fabric/DataEngineering, /fabric/ReportingHub, /fabric/ReportingInsights. Use / for the repository root."
  type        = string

  validation {
    condition     = startswith(var.git_folder, "/") && !can(regex("\\s|\\\\", var.git_folder))
    error_message = "git_folder must start with / and contain no spaces or backslashes, e.g. /fabric."
  }
}

variable "git_secret" {
  description = "GitHub: personal access token with Contents read/write on the repository. Azure DevOps: the executor's client secret. Set it through TF_VAR_git_secret (infra/Load-Credentials.ps1 does this) instead of typing it."
  type        = string
  sensitive   = true
  ephemeral   = true
}

variable "git_secret_version" {
  description = "Increase by 1 when the token or secret changes, so the Fabric connection is updated with the new value."
  type        = number
  default     = 1
}

variable "git_environments" {
  description = "Environments whose workspaces are connected to Git. Prod normally gets content through deployment instead."
  type        = list(string)
  default     = ["Dev"]
}

variable "git_initialization_strategy" {
  description = "What wins when both the workspace and the repository folder already have content. PreferWorkspace (default) never overwrites workspace items; PreferRemote updates the workspace from Git."
  type        = string
  default     = "PreferWorkspace"

  validation {
    condition     = contains(["PreferWorkspace", "PreferRemote"], var.git_initialization_strategy)
    error_message = "git_initialization_strategy must be PreferWorkspace or PreferRemote."
  }
}

variable "powershell" {
  description = "PowerShell used to create missing Git folders: powershell (Windows PowerShell) or pwsh (PowerShell 7, e.g. on Linux/GitHub Actions)."
  type        = string
  default     = "powershell"
}

# --- Access ------------------------------------------------------------------------

variable "orchestrator_admin" {
  description = "Add the person orchestrating the deployment as Admin on every workspace, so they can find and manage them. Should stay true."
  type        = bool
  default     = true
}

variable "orchestrator_object_id" {
  description = "Entra object ID of the orchestrator (user). Leave null to use the account signed in to Azure CLI (az login). Set it explicitly where az is signed in as a service principal, e.g. in GitHub Actions."
  type        = string
  default     = null
}

variable "workspace_name_prefix" {
  description = "Optional prefix for every workspace name, e.g. \"Contoso-\". Workspace names must be unique in the tenant."
  type        = string
  default     = ""
}

variable "data_engineering_folders" {
  description = "Workspace folders created in each DataEngineering workspace. 400_DataTransformation holds pipelines, notebooks, copy jobs etc. (created in Fabric, synced through Git)."
  type        = list(string)
  default     = ["100_Bronze", "200_Silver", "300_Gold", "400_DataTransformation"]
}

variable "lakehouses" {
  description = "Lakehouses created in each DataEngineering workspace: name => folder (one of data_engineering_folders, or null for the workspace root)."
  type        = map(string)
  default = {
    LH_Bronze = "100_Bronze"
  }

  validation {
    condition     = alltrue([for folder in values(var.lakehouses) : folder == null || contains(var.data_engineering_folders, folder)])
    error_message = "Every lakehouse folder must be one of data_engineering_folders (or null)."
  }
}

variable "lakehouse_enable_schemas" {
  description = "Create lakehouses with schemas enabled. Cannot be changed after creation."
  type        = bool
  default     = true
}

variable "warehouses" {
  description = "Warehouses created in each DataEngineering workspace: name => folder (one of data_engineering_folders, or null for the workspace root)."
  type        = map(string)
  default = {
    WH_Silver_Sources  = "200_Silver"
    WH_Silver_Models   = "200_Silver"
    WH_Gold_DataEstate = "300_Gold"
  }

  validation {
    condition     = alltrue([for folder in values(var.warehouses) : folder == null || contains(var.data_engineering_folders, folder)])
    error_message = "Every warehouse folder must be one of data_engineering_folders (or null)."
  }
}

variable "workspace_collation_confirmed" {
  description = "Set to true once the Data Warehouse collation of each DataEngineering workspace is set to case insensitive in the Fabric portal. Lakehouses are only created after that, because their SQL analytics endpoint takes the workspace collation at creation and can't be changed later."
  type        = bool
  default     = false
}

variable "warehouse_collation" {
  description = "Warehouse collation, set explicitly on every warehouse regardless of the workspace setting. Cannot be changed after creation. Default is case insensitive."
  type        = string
  default     = "Latin1_General_100_CI_AS_KS_WS_SC_UTF8"

  validation {
    condition     = contains(["Latin1_General_100_BIN2_UTF8", "Latin1_General_100_CI_AS_KS_WS_SC_UTF8"], var.warehouse_collation)
    error_message = "warehouse_collation must be Latin1_General_100_BIN2_UTF8 (case sensitive) or Latin1_General_100_CI_AS_KS_WS_SC_UTF8 (case insensitive)."
  }
}

variable "cross_workspace_access" {
  description = "Grants the workspace identity of a source workspace a role on a target workspace in the same environment. Values are workspace types: DataEngineering, ReportingHub, ReportingInsights."
  type = list(object({
    source = string
    target = string
    role   = string
  }))
  default = [
    # Semantic models in ReportingHub read the Gold warehouse in DataEngineering.
    { source = "ReportingHub", target = "DataEngineering", role = "Viewer" },
    # Reports in ReportingInsights build on the semantic models in ReportingHub.
    { source = "ReportingInsights", target = "ReportingHub", role = "Viewer" },
  ]

  validation {
    condition = alltrue([
      for a in var.cross_workspace_access :
      contains(["DataEngineering", "ReportingHub", "ReportingInsights"], a.source) &&
      contains(["DataEngineering", "ReportingHub", "ReportingInsights"], a.target) &&
      a.source != a.target &&
      contains(["Admin", "Member", "Contributor", "Viewer"], a.role)
    ])
    error_message = "source/target must be DataEngineering, ReportingHub or ReportingInsights (and differ); role must be Admin, Member, Contributor or Viewer."
  }
}

variable "additional_role_assignments" {
  description = "Extra workspace roles for Entra groups, users or service principals (e.g. an admin group, or a service principal used by semantic model connections). principal_id is the Entra object ID. Leave environments empty for all environments."
  type = list(object({
    workspace_type = string
    principal_id   = string
    principal_type = string
    role           = string
    environments   = optional(list(string), [])
  }))
  default = []

  validation {
    condition = alltrue([
      for a in var.additional_role_assignments :
      contains(["DataEngineering", "ReportingHub", "ReportingInsights"], a.workspace_type) &&
      contains(["Group", "User", "ServicePrincipal", "ServicePrincipalProfile"], a.principal_type) &&
      contains(["Admin", "Member", "Contributor", "Viewer"], a.role)
    ])
    error_message = "workspace_type must be DataEngineering, ReportingHub or ReportingInsights; principal_type must be Group, User, ServicePrincipal or ServicePrincipalProfile; role must be Admin, Member, Contributor or Viewer."
  }
}
