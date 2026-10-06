locals {
  workspace_types = {
    DataEngineering   = "Lakehouse and warehouses for ingestion and modelling (bronze, silver, gold)."
    ReportingHub      = "Shared semantic models built on the gold layer."
    ReportingInsights = "Reports built on the ReportingHub semantic models."
  }

  # One workspace per type and environment, keyed by its name without prefix,
  # e.g. "DataEngineeringDev".
  workspaces = merge([
    for env, cfg in var.environments : {
      for type, description in local.workspace_types : "${type}${env}" => {
        type        = type
        env         = env
        description = description
      }
    }
  ]...)

  data_engineering_workspaces = {
    for key, ws in local.workspaces : key => ws if ws.type == "DataEngineering"
  }

  lakehouses = merge([
    for ws_key, ws in local.data_engineering_workspaces : {
      for name in var.lakehouses : "${ws_key}/${name}" => { workspace_key = ws_key, name = name }
    }
  ]...)

  warehouses = merge([
    for ws_key, ws in local.data_engineering_workspaces : {
      for name in var.warehouses : "${ws_key}/${name}" => { workspace_key = ws_key, name = name }
    }
  ]...)

  # Workspace identity of <source><env> gets <role> on <target><env>.
  # Access never crosses environments.
  cross_workspace_access = merge([
    for env in keys(var.environments) : {
      for a in var.cross_workspace_access : "${a.target}${env}/${a.source}${env}" => {
        target_key = "${a.target}${env}"
        source_key = "${a.source}${env}"
        role       = a.role
      }
    }
  ]...)

  additional_role_assignments = merge([
    for env in keys(var.environments) : {
      for a in var.additional_role_assignments : "${a.workspace_type}${env}/${a.principal_id}" => {
        workspace_key  = "${a.workspace_type}${env}"
        principal_id   = a.principal_id
        principal_type = a.principal_type
        role           = a.role
      } if length(a.environments) == 0 || contains(a.environments, env)
    }
  ]...)
}

data "fabric_capacity" "this" {
  for_each = var.environments

  display_name = each.value.capacity_name

  lifecycle {
    postcondition {
      condition     = self.state == "Active"
      error_message = "Capacity ${each.value.capacity_name} is not active (state: ${self.state}). Resume it before deploying."
    }
  }
}

# The identity running Terraform creates the workspaces and therefore becomes
# their Admin automatically - no explicit role assignment is needed (and Fabric
# would reject a duplicate one).
resource "fabric_workspace" "this" {
  for_each = local.workspaces

  display_name = "${var.workspace_name_prefix}${each.key}"
  description  = each.value.description
  capacity_id  = data.fabric_capacity.this[each.value.env].id

  # Workspace identity: an Entra service principal managed by Fabric and tied
  # to this workspace, used for cross-workspace and data source access.
  identity = {
    type = "SystemAssigned"
  }
}

# Fabric has no API for the workspace's Data Warehouse collation, and a
# lakehouse's SQL analytics endpoint always takes that workspace collation at
# creation. So lakehouses wait until the setting has been changed by hand.
check "workspace_collation" {
  assert {
    condition     = var.workspace_collation_confirmed
    error_message = "Lakehouses are skipped. Set Workspace settings > Data Warehouse > Collations to 'Case insensitive' in each workspace, then re-run with workspace_collation_confirmed = true."
  }
}

resource "fabric_lakehouse" "this" {
  for_each = { for key, lh in local.lakehouses : key => lh if var.workspace_collation_confirmed }

  display_name = each.value.name
  workspace_id = fabric_workspace.this[each.value.workspace_key].id

  configuration = {
    enable_schemas = var.lakehouse_enable_schemas
  }
}

resource "fabric_warehouse" "this" {
  for_each = local.warehouses

  display_name = each.value.name
  workspace_id = fabric_workspace.this[each.value.workspace_key].id

  configuration = {
    collation_type = var.warehouse_collation
  }
}

resource "fabric_workspace_role_assignment" "cross_workspace" {
  for_each = local.cross_workspace_access

  workspace_id = fabric_workspace.this[each.value.target_key].id
  role         = each.value.role

  principal = {
    id   = fabric_workspace.this[each.value.source_key].identity.service_principal_id
    type = "ServicePrincipal"
  }
}

resource "fabric_workspace_role_assignment" "additional" {
  for_each = local.additional_role_assignments

  workspace_id = fabric_workspace.this[each.value.workspace_key].id
  role         = each.value.role

  principal = {
    id   = each.value.principal_id
    type = each.value.principal_type
  }
}
