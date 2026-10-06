locals {
  platform = jsondecode(file("${path.module}/../platform.json"))

  subscription_id = coalesce(var.subscription_id, local.platform.subscription_id)
  key_vault_name  = coalesce(var.key_vault_name, local.platform.key_vault_name)

  service_principals = coalesce(var.service_principals, {
    executor-client-secret = local.platform.executor_client_id
  })

  key_vault = one(data.azurerm_resources.key_vault.resources)
}

data "azurerm_resources" "key_vault" {
  type = "Microsoft.KeyVault/vaults"
  name = local.key_vault_name

  lifecycle {
    postcondition {
      condition     = length(self.resources) == 1
      error_message = "Key Vault ${local.key_vault_name} not found in subscription ${local.subscription_id}."
    }
  }
}

# The truth about a client secret's expiry is in Entra, not in Key Vault (the
# vault copy may have no expiry date). Uses the newest secret of each app.
data "external" "client_secret_expiry" {
  for_each = local.service_principals

  program = ["az", "ad", "app", "credential", "list", "--id", each.value, "--query", "{ends: max_by(@, &endDateTime).endDateTime}", "--output", "json"]
}

module "expiry_alerts" {
  source = "../modules/expiry-alerts"

  name_prefix              = local.key_vault_name
  resource_group_name      = local.key_vault.resource_group_name
  location                 = local.key_vault.location
  key_vault_id             = local.key_vault.id
  key_vault_name           = local.key_vault_name
  existing_system_topic_id = var.existing_system_topic_id
  alert_email_addresses    = var.alert_email_addresses
  warning_days             = var.expiry_warning_days
  send_test_alert          = var.send_test_alert

  credentials = merge(
    { for label, e in data.external.client_secret_expiry : label => e.result.ends },
    var.extra_credentials,
  )

  tags = {
    workload   = "fabric-data-platform"
    managed_by = "terraform"
  }
}
