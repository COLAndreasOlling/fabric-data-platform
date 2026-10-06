# The first four variables have no default, so Terraform prompts for them.
# To skip the prompts, put them in terraform.tfvars (see terraform.tfvars.example).

variable "subscription_id" {
  description = "Azure subscription ID that hosts the platform (GUID)."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F-]{36}$", var.subscription_id))
    error_message = "subscription_id must be a GUID, e.g. 00000000-0000-0000-0000-000000000000."
  }
}

variable "company_code" {
  description = "Company indicator, 2-4 letters (e.g. cg for Columbus Global)."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z]{2,4}$", var.company_code))
    error_message = "company_code must be 2-4 letters, e.g. cg."
  }
}

variable "location" {
  description = "Azure region (e.g. westeurope, northeurope, swedencentral)."
  type        = string

  validation {
    condition = contains([
      "westeurope", "northeurope", "swedencentral", "norwayeast", "denmarkeast",
      "germanywestcentral", "francecentral", "uksouth", "eastus", "eastus2", "westus2",
    ], lower(var.location))
    error_message = "Unsupported location. Use e.g. westeurope, northeurope or swedencentral (or add it to region_abbreviations in main.tf)."
  }
}

variable "platform_version" {
  description = "Platform version, two digits (e.g. 01)."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{2}$", var.platform_version))
    error_message = "platform_version must be two digits, e.g. 01."
  }
}

variable "alert_email_addresses" {
  description = "Who is warned before the executor's client secret and the GitHub token expire: one or more email addresses, separated by commas (e.g. dataplatform@customer.com, consultant@columbusglobal.com). A shared mailbox is better than one person."
  type        = string

  validation {
    condition = length(compact(split(",", var.alert_email_addresses))) > 0 && alltrue([
      for a in compact(split(",", var.alert_email_addresses)) : can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", trimspace(a)))
    ])
    error_message = "Enter one or more email addresses separated by commas, e.g. dataplatform@customer.com, me@columbusglobal.com."
  }
}

variable "expiry_warning_days" {
  description = "Days before expiry of the first warning. Further warnings come 30 days before and on the expiry day."
  type        = number
  default     = 90

  validation {
    condition     = var.expiry_warning_days > 30 && var.expiry_warning_days <= 365
    error_message = "expiry_warning_days must be between 31 and 365 (30 days and expiry are always warned about)."
  }
}

variable "environments" {
  description = "Environments and their one-letter name prefix. Keys are used in workspace names (e.g. DataEngineeringDev)."
  type        = map(string)
  default = {
    Dev  = "d"
    Prod = "p"
  }

  validation {
    condition     = alltrue([for letter in values(var.environments) : can(regex("^[a-z]$", letter))])
    error_message = "Each environment prefix must be a single lowercase letter."
  }
}

variable "key_vault_environment" {
  description = "Environment whose resource group holds the Key Vault with the executor's credentials."
  type        = string
  default     = "Prod"
}

variable "key_vault_purge_protection" {
  description = "Enable purge protection on the Key Vault. Recommended; note it can't be turned off again and a deleted vault name stays reserved for the retention period."
  type        = bool
  default     = true
}

variable "client_secret_validity_days" {
  description = "Client secret lifetime in days. 730 (2 years) is the maximum Entra allows in the portal and the default here; re-running bootstrap after expiry rotates it."
  type        = number
  default     = 730

  validation {
    condition     = var.client_secret_validity_days >= 1 && var.client_secret_validity_days <= 730
    error_message = "client_secret_validity_days must be between 1 and 730."
  }
}

variable "additional_owners" {
  description = "Extra object IDs (users or service principals) to add as owners of the app registration, service principal and group. The person running bootstrap is always an owner - required with the Application Developer role."
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
