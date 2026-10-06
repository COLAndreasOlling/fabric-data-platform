variable "subscription_id" {
  description = "Azure subscription that hosts the Fabric capacities."
  type        = string
}

variable "location" {
  description = "Azure region for the capacity resource group."
  type        = string
  default     = "westeurope"
}

variable "resource_group_name" {
  description = "Resource group for the capacities. Created here; the executor gets Contributor on it."
  type        = string
  default     = "rg-fabric-capacities"
}

variable "executor_name" {
  description = "Display name of the app registration / service principal that runs Terraform."
  type        = string
  default     = "sp-fabric-terraform"
}

variable "executor_group_name" {
  description = "Security group containing the executor. Used to scope Fabric tenant settings."
  type        = string
  default     = "sg-fabric-terraform-executors"
}

variable "entra_owners" {
  description = "Object IDs set as owners of the app registration, service principal and group. Empty keeps them ownerless (manage them with the Application/Groups Administrator role)."
  type        = list(string)
  default     = []
}

variable "github_repository" {
  description = "GitHub repository (owner/name) allowed to sign in as the executor through OIDC. Set to null to skip."
  type        = string
  default     = "COLAndreasOlling/fabric-data-platform"
}

variable "github_subjects" {
  description = "GitHub OIDC subjects (after \"repo:<owner>/<name>:\") that may sign in, e.g. a branch, pull requests or an environment."
  type        = list(string)
  default     = ["ref:refs/heads/main", "pull_request"]
}

variable "create_client_secret" {
  description = "Create a client secret for local runs. Not needed for GitHub Actions (OIDC)."
  type        = bool
  default     = true
}

variable "client_secret_validity" {
  description = "How long the client secret is valid, as a duration (e.g. 720h = 30 days)."
  type        = string
  default     = "2160h"
}

variable "manage_fabric_tenant_settings" {
  description = "Add the executor group to the Fabric tenant settings below. Requires the Fabric Administrator role. Existing groups are kept; settings already enabled for the whole organization are left alone."
  type        = bool
  default     = false
}

variable "fabric_tenant_settings" {
  description = "Fabric tenant settings (API names) the executor group needs."
  type        = list(string)
  default = [
    "ServicePrincipalAccessGlobalAPIs",     # Service principals can create workspaces, connections, and deployment pipelines
    "ServicePrincipalAccessPermissionAPIs", # Service principals can call Fabric public APIs
  ]
}
