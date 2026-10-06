# Fabric items are owned by the identity that creates them. To keep ownership
# away from personal accounts, this provider only accepts a service principal
# (client secret, certificate or OIDC) or a managed identity - Azure CLI logins
# are disabled on purpose.
#
# Supply credentials through environment variables, e.g.:
#   FABRIC_TENANT_ID, FABRIC_CLIENT_ID and FABRIC_CLIENT_SECRET (local runs)
#   FABRIC_TENANT_ID, FABRIC_CLIENT_ID and FABRIC_USE_OIDC=true (GitHub Actions)
provider "fabric" {
  use_cli     = false
  use_dev_cli = false
}
