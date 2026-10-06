# Bootstrap is the one configuration that runs with a personal admin login
# (`az login`): it creates the executor service principal that everything else
# runs as, so it can't use that principal itself. It creates no Fabric items
# and doesn't change Fabric tenant settings.

provider "azuread" {}

provider "azurerm" {
  features {
    key_vault {
      # Never purge the vault or its secrets on destroy - soft delete only.
      purge_soft_delete_on_destroy          = false
      purge_soft_deleted_secrets_on_destroy = false
    }
  }

  subscription_id = var.subscription_id

  # Register only what this platform needs.
  resource_provider_registrations = "none"
  resource_providers_to_register  = ["Microsoft.Fabric", "Microsoft.KeyVault"]
}
