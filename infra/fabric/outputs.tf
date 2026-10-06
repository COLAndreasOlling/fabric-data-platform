output "workspaces" {
  description = "Workspaces with their IDs and workspace identity."
  value = {
    for key, ws in fabric_workspace.this : key => {
      id                            = ws.id
      display_name                  = ws.display_name
      identity_application_id       = ws.identity.application_id
      identity_service_principal_id = ws.identity.service_principal_id
    }
  }
}

output "orchestrator" {
  description = "User added as Admin on every workspace."
  value       = var.orchestrator_admin ? coalesce(one(data.external.orchestrator[*].result.upn), local.orchestrator_object_id) : null
}

output "lakehouses" {
  description = "Lakehouse IDs and SQL endpoint connection strings."
  value = {
    for key, lh in fabric_lakehouse.this : key => {
      id                    = lh.id
      sql_connection_string = lh.properties.sql_endpoint_properties.connection_string
    }
  }
}

output "warehouses" {
  description = "Warehouse IDs and connection strings."
  value = {
    for key, wh in fabric_warehouse.this : key => {
      id                = wh.id
      connection_string = wh.properties.connection_string
    }
  }
}
