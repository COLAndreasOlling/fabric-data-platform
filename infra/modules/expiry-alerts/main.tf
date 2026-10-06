# Email warnings before credentials expire, built on Key Vault events:
#
#   Key Vault (SecretNearExpiry 30 days before, SecretExpired on the day)
#     -> Event Grid system topic -> Azure Monitor alert -> action group (email)
#
# Key Vault's warning is fixed at 30 days, so for every credential this module
# writes two *marker* secrets (no credential in them, just a message):
#
#   expiry-<label>-early  expires (warning_days - 30) days before the credential
#                         -> emails at warning_days and (warning_days - 30) days before
#   expiry-<label>        expires with the credential
#                         -> emails 30 days before and on the day
#
# The subscription only listens to secrets named expiry-*, so real secrets never
# send duplicate or confusing alerts. Key Vault only raises these events for
# secret versions written after the subscription exists - the markers depend on it.

terraform {
  required_providers {
    azurerm = { source = "hashicorp/azurerm" }
    azapi   = { source = "azure/azapi" }
    time    = { source = "hashicorp/time" }
  }
}

locals {
  emails = toset([for a in compact(split(",", var.alert_email_addresses)) : lower(trimspace(a))])

  markers = merge([
    for label, expires in var.credentials : {
      "expiry-${label}-early" = {
        label   = label
        expires = timeadd(expires, "-${(var.warning_days - 30) * 24}h")
        message = "${label} expires ${expires}. First warning (${var.warning_days} days ahead) - plan the renewal. ${var.renewal_instructions}"
      }
      "expiry-${label}" = {
        label   = label
        expires = expires
        message = "${label} expires ${expires}. ${var.renewal_instructions}"
      }
    }
  ]...)
}

resource "azurerm_monitor_action_group" "this" {
  name                = "${var.name_prefix}-ag-secret-expiry"
  resource_group_name = var.resource_group_name
  short_name          = "secexpiry"
  tags                = var.tags

  dynamic "email_receiver" {
    for_each = local.emails
    content {
      name                    = email_receiver.value
      email_address           = email_receiver.value
      use_common_alert_schema = true
    }
  }
}

resource "azurerm_eventgrid_system_topic" "this" {
  count = var.existing_system_topic_id == null ? 1 : 0

  name                = "${var.key_vault_name}-events"
  resource_group_name = var.resource_group_name
  location            = var.location
  source_resource_id  = var.key_vault_id
  topic_type          = "Microsoft.KeyVault.vaults"
  tags                = var.tags
}

resource "azapi_resource" "subscription" {
  type      = "Microsoft.EventGrid/systemTopics/eventSubscriptions@2025-02-15"
  name      = "credential-expiry-alerts"
  parent_id = coalesce(var.existing_system_topic_id, one(azurerm_eventgrid_system_topic.this[*].id))

  body = {
    properties = {
      destination = {
        endpointType = "MonitorAlert"
        properties = {
          severity     = "Sev2"
          description  = "A credential tracked in ${var.key_vault_name} is about to expire or has expired. The secret name (expiry-<credential>) says which. ${var.renewal_instructions}"
          actionGroups = [azurerm_monitor_action_group.this.id]
        }
      }
      filter = {
        subjectBeginsWith  = "expiry-"
        includedEventTypes = ["Microsoft.KeyVault.SecretNearExpiry", "Microsoft.KeyVault.SecretExpired"]
      }
      # The Azure Monitor alert destination only accepts CloudEvents 1.0.
      eventDeliverySchema = "CloudEventSchemaV1_0"
    }
  }
}

resource "azurerm_key_vault_secret" "marker" {
  for_each = local.markers

  name            = each.key
  value           = each.value.message
  content_type    = "Expiry marker for ${each.value.label} (not a credential)"
  expiration_date = each.value.expires
  key_vault_id    = var.key_vault_id

  depends_on = [azapi_resource.subscription]
}

# Optional: a marker that expires a few minutes after apply, to see the alert
# emails end to end. Remove with send_test_alert = false afterwards.
resource "time_static" "test" {
  count = var.send_test_alert ? 1 : 0
}

resource "azurerm_key_vault_secret" "test" {
  count = var.send_test_alert ? 1 : 0

  name            = "expiry-alert-test-${time_static.test[0].unix}"
  value           = "Test of the credential expiry alerts - safe to ignore."
  content_type    = "Expiry alert test (not a credential)"
  expiration_date = timeadd(time_static.test[0].rfc3339, "10m")
  key_vault_id    = var.key_vault_id

  depends_on = [azapi_resource.subscription]
}
