output "tenant_id" {
  description = "Use as ARM_TENANT_ID / FABRIC_TENANT_ID."
  value       = data.azuread_client_config.current.tenant_id
}

output "client_id" {
  description = "Use as ARM_CLIENT_ID / FABRIC_CLIENT_ID."
  value       = azuread_application.executor.client_id
}

output "service_principal_object_id" {
  description = "Object ID of the executor service principal."
  value       = azuread_service_principal.executor.object_id
}

output "executor_group_object_id" {
  description = "Object ID of the executor security group (for tenant settings)."
  value       = azuread_group.executors.object_id
}

output "resource_group_name" {
  description = "Resource group for ../ (capacities)."
  value       = azurerm_resource_group.capacities.name
}

output "client_secret" {
  description = "Client secret for local runs. Show with: terraform output -raw client_secret"
  value       = try(azuread_application_password.local[0].value, null)
  sensitive   = true
}

output "tenant_settings_updated" {
  description = "Tenant settings that had the executor group added (others were already enabled for everyone, or not managed)."
  value       = keys(fabric_tenant_setting.executor)
}
