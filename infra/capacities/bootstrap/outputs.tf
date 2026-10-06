output "names" {
  description = "Generated resource names per environment."
  value       = local.environments
}

output "executor" {
  description = "Executor service principal."
  value = {
    name            = local.executor_name
    client_id       = azuread_application.executor.client_id
    object_id       = azuread_service_principal.executor.object_id
    secret_expires  = azuread_application_password.executor.end_date
    group_name      = azuread_group.executors.display_name
    group_object_id = azuread_group.executors.object_id
  }
}

output "key_vault_name" {
  description = "Key Vault holding executor-client-id, executor-client-secret and executor-tenant-id."
  value       = azurerm_key_vault.this.name
}
