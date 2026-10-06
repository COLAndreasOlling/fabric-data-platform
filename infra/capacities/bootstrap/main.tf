data "azuread_client_config" "current" {}

# --- Naming --------------------------------------------------------------------
# <env>-<company>-<region>-dp-<version>-da[-<resource>], e.g.
#   p-cg-we-dp-01-da      resource group
#   p-cg-we-dp-01-da-kv   key vault
#   pcgwedp01dafab        Fabric capacity (Azure allows only lowercase letters
#                         and digits in capacity names, so hyphens are dropped)

locals {
  region_abbreviations = {
    westeurope         = "we"
    northeurope        = "ne"
    swedencentral      = "sc"
    norwayeast         = "no"
    denmarkeast        = "dk"
    germanywestcentral = "gw"
    francecentral      = "fc"
    uksouth            = "uks"
    eastus             = "eus"
    eastus2            = "eus2"
    westus2            = "wus2"
  }

  location = lower(var.location)
  company  = lower(var.company_code)
  region   = local.region_abbreviations[local.location]

  # Shared, environment-less part, used for the executor identity.
  platform_name = "${local.company}-${local.region}-dp-${var.platform_version}-da"

  environments = {
    for env, letter in var.environments : env => {
      resource_group = "${letter}-${local.platform_name}"
      capacity_name  = replace("${letter}-${local.platform_name}-fab", "-", "")
    }
  }

  key_vault_name = "${local.environments[var.key_vault_environment].resource_group}-kv"
  executor_name  = "${local.platform_name}-sp-terraform"
  group_name     = "${local.platform_name}-sg-terraform-executors"

  owners = distinct(concat([data.azuread_client_config.current.object_id], var.additional_owners))

  tags = {
    workload   = "fabric-data-platform"
    managed_by = "terraform"
  }
}

# --- Executor identity ---------------------------------------------------------
# The person running bootstrap stays owner of these Entra objects: with the
# Application Developer role you can only manage apps you own. Fabric items and
# capacities are created by the service principal, never by a person.

resource "azuread_application" "executor" {
  display_name     = local.executor_name
  sign_in_audience = "AzureADMyOrg"
  owners           = local.owners
}

resource "azuread_service_principal" "executor" {
  client_id = azuread_application.executor.client_id
  owners    = local.owners
}

# GitHub Actions signs in without a stored secret.
resource "azuread_application_federated_identity_credential" "github" {
  for_each = var.github_repository == null ? toset([]) : toset(var.github_subjects)

  application_id = azuread_application.executor.id
  display_name   = "github-${replace(replace(each.value, "/[^a-zA-Z0-9-]/", "-"), "/-+/", "-")}"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${var.github_repository}:${each.value}"
}

# Client secret for local runs. Re-running bootstrap after it expires creates a
# new one and updates Key Vault.
resource "time_rotating" "client_secret" {
  rotation_days = var.client_secret_validity_days
}

resource "azuread_application_password" "executor" {
  application_id = azuread_application.executor.id
  display_name   = "terraform-${formatdate("YYYY-MM-DD", time_rotating.client_secret.rfc3339)}"
  end_date       = time_rotating.client_secret.rotation_rfc3339

  rotate_when_changed = {
    rotation = time_rotating.client_secret.id
  }
}

# A Fabric administrator adds this group to the tenant settings for service
# principals (see README) - bootstrap doesn't change tenant settings.
resource "azuread_group" "executors" {
  display_name     = local.group_name
  description      = "Identities allowed to deploy the Fabric data platform. Add to the Fabric tenant settings for service principals."
  security_enabled = true
  owners           = local.owners
  members          = [azuread_service_principal.executor.object_id]
}

# --- Azure: one resource group per environment ---------------------------------

resource "azurerm_resource_group" "this" {
  for_each = local.environments

  name     = each.value.resource_group
  location = local.location
  tags     = local.tags
}

resource "azurerm_role_assignment" "executor_contributor" {
  for_each = azurerm_resource_group.this

  scope                = each.value.id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.executor.object_id
  principal_type       = "ServicePrincipal"
}

# --- Key Vault with the executor's credentials --------------------------------

resource "azurerm_key_vault" "this" {
  name                       = local.key_vault_name
  location                   = local.location
  resource_group_name        = azurerm_resource_group.this[var.key_vault_environment].name
  tenant_id                  = data.azuread_client_config.current.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
  purge_protection_enabled   = var.key_vault_purge_protection
  soft_delete_retention_days = 90
  tags                       = local.tags

  lifecycle {
    precondition {
      condition     = length(local.key_vault_name) <= 24
      error_message = "Key Vault name ${local.key_vault_name} is longer than 24 characters. Use a shorter company_code."
    }
  }
}

# Lets the person running bootstrap write and read the secrets.
resource "azurerm_role_assignment" "bootstrap_secrets_officer" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azuread_client_config.current.object_id
}

# Role assignments take a moment to apply in Key Vault.
resource "time_sleep" "key_vault_rbac" {
  create_duration = "90s"
  depends_on      = [azurerm_role_assignment.bootstrap_secrets_officer]
}

# --- Expiry warnings -------------------------------------------------------------
# Key Vault raises SecretNearExpiry 30 days before a secret expires and
# SecretExpired on the day; Event Grid turns them into Azure Monitor alerts that
# email alert_email_addresses. This covers every secret in the vault with an
# expiry date: the executor's client secret and the GitHub token
# (Save-GitToken.ps1). For an earlier warning, a reminder secret per credential
# expires (expiry_warning_days - 30) days before the real one, so its "near
# expiry" alert arrives expiry_warning_days ahead.
#
# Key Vault only raises these events for secret versions written after the
# subscription exists - so all secrets below depend on it.

resource "azurerm_monitor_action_group" "expiry" {
  name                = "${local.platform_name}-ag-secret-expiry"
  resource_group_name = azurerm_resource_group.this[var.key_vault_environment].name
  short_name          = "secexpiry"
  tags                = local.tags

  dynamic "email_receiver" {
    for_each = toset([for a in compact(split(",", var.alert_email_addresses)) : lower(trimspace(a))])
    content {
      name                    = email_receiver.value
      email_address           = email_receiver.value
      use_common_alert_schema = true
    }
  }
}

resource "azurerm_eventgrid_system_topic" "key_vault" {
  name                = "${local.key_vault_name}-events"
  resource_group_name = azurerm_resource_group.this[var.key_vault_environment].name
  location            = local.location
  source_resource_id  = azurerm_key_vault.this.id
  topic_type          = "Microsoft.KeyVault.vaults"
  tags                = local.tags
}

resource "azapi_resource" "expiry_alerts" {
  type      = "Microsoft.EventGrid/systemTopics/eventSubscriptions@2025-02-15"
  name      = "secret-expiry-alerts"
  parent_id = azurerm_eventgrid_system_topic.key_vault.id

  body = {
    properties = {
      destination = {
        endpointType = "MonitorAlert"
        properties = {
          severity     = "Sev2"
          description  = "A secret in ${local.key_vault_name} is about to expire or has expired. See docs/terraform-setup-guide.md, 'Rotating secrets'."
          actionGroups = [azurerm_monitor_action_group.expiry.id]
        }
      }
      filter = {
        includedEventTypes = ["Microsoft.KeyVault.SecretNearExpiry", "Microsoft.KeyVault.SecretExpired"]
      }
      eventDeliverySchema = "EventGridSchema"
    }
  }
}

resource "azurerm_key_vault_secret" "client_secret" {
  name            = "executor-client-secret"
  value           = azuread_application_password.executor.value
  content_type    = "Client secret for ${local.executor_name}"
  expiration_date = azuread_application_password.executor.end_date
  key_vault_id    = azurerm_key_vault.this.id
  depends_on      = [time_sleep.key_vault_rbac, azapi_resource.expiry_alerts]
}

# Exists only to trigger the early warning; the value is a reminder text.
resource "azurerm_key_vault_secret" "client_secret_reminder" {
  name            = "executor-client-secret-renewal-reminder"
  value           = "executor-client-secret expires ${azuread_application_password.executor.end_date}. Renew it by running infra/capacities/bootstrap again - see docs/terraform-setup-guide.md, 'Rotating secrets'."
  content_type    = "Reminder (not a credential)"
  expiration_date = timeadd(azuread_application_password.executor.end_date, "-${(var.expiry_warning_days - 30) * 24}h")
  key_vault_id    = azurerm_key_vault.this.id
  depends_on      = [time_sleep.key_vault_rbac, azapi_resource.expiry_alerts]
}

resource "azurerm_key_vault_secret" "client_id" {
  name         = "executor-client-id"
  value        = azuread_application.executor.client_id
  content_type = "Client (application) ID of ${local.executor_name}"
  key_vault_id = azurerm_key_vault.this.id
  depends_on   = [time_sleep.key_vault_rbac]
}

resource "azurerm_key_vault_secret" "tenant_id" {
  name         = "executor-tenant-id"
  value        = data.azuread_client_config.current.tenant_id
  content_type = "Entra tenant ID"
  key_vault_id = azurerm_key_vault.this.id
  depends_on   = [time_sleep.key_vault_rbac]
}

# --- Shared settings for ../ and ../../fabric ---------------------------------
# Names and IDs only, no secrets - safe to commit.

resource "local_file" "platform" {
  filename = "${path.module}/../../platform.json"
  content = "${jsonencode({
    subscription_id    = var.subscription_id
    tenant_id          = data.azuread_client_config.current.tenant_id
    location           = local.location
    executor_client_id = azuread_application.executor.client_id
    key_vault_name     = azurerm_key_vault.this.name
    environments       = local.environments
  })}\n"
}
