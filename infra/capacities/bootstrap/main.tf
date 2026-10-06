data "azuread_client_config" "current" {}

# --- Executor identity ---------------------------------------------------------

resource "azuread_application" "executor" {
  display_name     = var.executor_name
  sign_in_audience = "AzureADMyOrg"
  owners           = var.entra_owners
}

resource "azuread_service_principal" "executor" {
  client_id = azuread_application.executor.client_id
  owners    = var.entra_owners
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

# For local runs only. The value ends up in this configuration's state file,
# which is git-ignored - keep it that way.
resource "azuread_application_password" "local" {
  count = var.create_client_secret ? 1 : 0

  application_id    = azuread_application.executor.id
  display_name      = "local-terraform"
  end_date_relative = var.client_secret_validity
}

resource "azuread_group" "executors" {
  display_name     = var.executor_group_name
  description      = "Identities allowed to deploy the Fabric data platform. Used to scope Fabric tenant settings."
  security_enabled = true
  owners           = var.entra_owners
  members          = [azuread_service_principal.executor.object_id]
}

# --- Azure: resource group for the capacities --------------------------------

resource "azurerm_resource_group" "capacities" {
  name     = var.resource_group_name
  location = var.location
  tags = {
    workload   = "fabric-data-platform"
    managed_by = "terraform"
  }
}

resource "azurerm_role_assignment" "executor_contributor" {
  scope                = azurerm_resource_group.capacities.id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.executor.object_id
  principal_type       = "ServicePrincipal"
}

# --- Fabric tenant settings (opt-in) -------------------------------------------
# A tenant setting update replaces its whole group list, so the current groups
# are read first and the executor group is added to them. Settings that are
# already enabled for the entire organization already cover the executor and
# are not touched.

data "fabric_tenant_setting" "current" {
  for_each = var.manage_fabric_tenant_settings ? toset(var.fabric_tenant_settings) : toset([])

  setting_name = each.value
}

locals {
  tenant_settings_to_update = {
    for name, s in data.fabric_tenant_setting.current : name => s
    if !(s.enabled && length(coalesce(s.enabled_security_groups, [])) == 0)
  }
}

resource "fabric_tenant_setting" "executor" {
  for_each = local.tenant_settings_to_update

  setting_name     = each.key
  enabled          = true
  delete_behaviour = "NoChange"

  enabled_security_groups = setunion(
    [for g in coalesce(each.value.enabled_security_groups, []) : { graph_id = g.graph_id }],
    [{ graph_id = azuread_group.executors.object_id }],
  )

  excluded_security_groups = [
    for g in coalesce(each.value.excluded_security_groups, []) : { graph_id = g.graph_id }
  ]
}
