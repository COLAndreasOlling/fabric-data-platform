variable "name_prefix" {
  description = "Prefix for the action group name, e.g. cg-we-dp-01-da."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group of the Key Vault; the alert resources are created there."
  type        = string
}

variable "location" {
  description = "Location of the Key Vault."
  type        = string
}

variable "key_vault_id" {
  description = "Resource ID of the Key Vault."
  type        = string
}

variable "key_vault_name" {
  description = "Name of the Key Vault."
  type        = string
}

variable "existing_system_topic_id" {
  description = "A Key Vault can have only one Event Grid system topic. If it already has one, pass its resource ID to reuse it."
  type        = string
  default     = null
}

variable "alert_email_addresses" {
  description = "Recipients, separated by commas."
  type        = string
}

variable "warning_days" {
  description = "Days before expiry of the first warning (31-365)."
  type        = number
  default     = 90
}

variable "credentials" {
  description = "Credentials to warn about: label => expiry (RFC 3339). The label becomes part of a Key Vault secret name: letters, digits and dashes."
  type        = map(string)

  validation {
    condition     = alltrue([for label in keys(var.credentials) : can(regex("^[0-9A-Za-z-]{1,100}$", label))])
    error_message = "Credential labels may only contain letters, digits and dashes."
  }
}

variable "renewal_instructions" {
  description = "Text included in the alert and marker secrets on how to renew."
  type        = string
  default     = "See docs/terraform-setup-guide.md, 'Expiring credentials and warnings'."
}

variable "send_test_alert" {
  description = "Create a marker that expires 10 minutes after apply, to test the emails."
  type        = bool
  default     = false
}

variable "tags" {
  type    = map(string)
  default = {}
}
