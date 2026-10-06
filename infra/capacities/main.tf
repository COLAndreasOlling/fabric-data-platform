data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "this" {
  count = var.create_resource_group ? 1 : 0

  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# Capacities are billed while they are running - pause them in the Azure
# portal when not in use.
resource "azurerm_fabric_capacity" "this" {
  for_each = var.capacities

  name                = each.value.name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  # The service principal running Terraform must be capacity admin so the
  # Fabric configuration (../fabric) can assign workspaces to the capacity.
  administration_members = setunion([data.azurerm_client_config.current.object_id], var.capacity_admins)

  sku {
    name = each.value.sku
    tier = "Fabric"
  }

  depends_on = [azurerm_resource_group.this]
}
