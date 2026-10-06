# Runs as the person signed in to Azure CLI (az login), like bootstrap: it only
# adds alerting around an existing Key Vault and creates no Fabric items.
# Bootstrap already includes these alerts - use this configuration for vaults
# that bootstrap didn't create (existing environments).

provider "azurerm" {
  features {}

  subscription_id = local.subscription_id

  resource_provider_registrations = "none"
  resource_providers_to_register  = ["Microsoft.EventGrid", "Microsoft.Insights"]
}

provider "azapi" {
  subscription_id = local.subscription_id
}
