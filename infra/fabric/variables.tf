# Environments and capacity names come from ../platform.json (written by
# ../capacities/bootstrap). Override a capacity here to use an existing one.
variable "capacity_name_overrides" {
  description = "Use an existing Fabric capacity for an environment, e.g. { Dev = \"mytrialcapacity\" }."
  type        = map(string)
  default     = {}
}

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

variable "lakehouses" {
  description = "Lakehouses created in each DataEngineering workspace."
  type        = list(string)
  default     = ["LH_Bronze"]
}

variable "lakehouse_enable_schemas" {
  description = "Create lakehouses with schemas enabled. Cannot be changed after creation."
  type        = bool
  default     = true
}

variable "warehouses" {
  description = "Warehouses created in each DataEngineering workspace."
  type        = list(string)
  default     = ["WH_Silver_Sources", "WH_Silver_Models", "WH_Gold_DataEstate"]
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
