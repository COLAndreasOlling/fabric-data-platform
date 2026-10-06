# Like the Fabric configuration, this runs only as a service principal
# (client secret, certificate or OIDC) or a managed identity - Azure CLI logins
# are disabled on purpose.
#
# Supply credentials through environment variables, e.g.:
#   ARM_TENANT_ID, ARM_CLIENT_ID and ARM_CLIENT_SECRET (local runs)
#   ARM_TENANT_ID, ARM_CLIENT_ID and ARM_USE_OIDC=true (GitHub Actions)
provider "azurerm" {
  features {}

  subscription_id = var.subscription_id
  use_cli         = false

  # The executor only has Contributor on the resource group, so it can't
  # register resource providers - bootstrap/ registers Microsoft.Fabric.
  resource_provider_registrations = "none"
}
