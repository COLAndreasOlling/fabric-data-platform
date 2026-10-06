variable "alert_email_addresses" {
  description = "Who is warned before the credentials expire: one or more email addresses, separated by commas. A shared mailbox is better than one person."
  type        = string

  validation {
    condition = length(compact(split(",", var.alert_email_addresses))) > 0 && alltrue([
      for a in compact(split(",", var.alert_email_addresses)) : can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", trimspace(a)))
    ])
    error_message = "Enter one or more email addresses separated by commas, e.g. dataplatform@customer.com, me@columbusglobal.com."
  }
}

variable "expiry_warning_days" {
  description = "Days before expiry of the first warning. Further warnings follow 30 days later, 30 days before and on the day."
  type        = number
  default     = 90

  validation {
    condition     = var.expiry_warning_days > 30 && var.expiry_warning_days <= 365
    error_message = "expiry_warning_days must be between 31 and 365."
  }
}

variable "service_principals" {
  description = "Service principals whose client secret expiry to warn about: label => client (application) ID. The expiry is read from Entra (the newest secret). Default: the executor from ../platform.json."
  type        = map(string)
  default     = null
}

variable "extra_credentials" {
  description = "Other credentials to warn about, with a known expiry: label => date (RFC 3339, e.g. 2027-03-31T00:00:00Z). GitHub tokens are handled by infra/Save-GitToken.ps1."
  type        = map(string)
  default     = {}
}

variable "key_vault_name" {
  description = "Key Vault to attach the alerts to. Default: key_vault_name from ../platform.json."
  type        = string
  default     = null
}

variable "subscription_id" {
  description = "Subscription of the Key Vault. Default: subscription_id from ../platform.json."
  type        = string
  default     = null
}

variable "existing_system_topic_id" {
  description = "Resource ID of the vault's existing Event Grid system topic, if it has one (a vault can only have one)."
  type        = string
  default     = null
}

variable "send_test_alert" {
  description = "Create a marker secret that expires 10 minutes after apply, to see the alert emails. Set back to false afterwards."
  type        = bool
  default     = false
}
