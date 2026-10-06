# Bootstrap is the one configuration that runs with a personal admin login
# (`az login`): it creates the executor service principal that everything else
# runs as, so it can't use that principal itself. It creates no Fabric items,
# only identities, permissions and (optionally) tenant settings.

provider "azuread" {}

provider "azurerm" {
  features {}

  subscription_id = var.subscription_id

  # Register only what this platform needs.
  resource_provider_registrations = "none"
  resource_providers_to_register  = ["Microsoft.Fabric"]
}

provider "fabric" {
  use_cli = true
}
