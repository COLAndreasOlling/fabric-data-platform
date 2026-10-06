locals {
  # Written by bootstrap/.
  platform = jsondecode(file("${path.module}/../platform.json"))
}

data "azurerm_client_config" "current" {}

# Capacities are billed while they are running - pause them in the Azure
# portal when not in use.
resource "azurerm_fabric_capacity" "this" {
  for_each = local.platform.environments

  name                = each.value.capacity_name
  resource_group_name = each.value.resource_group
  location            = local.platform.location
  tags                = var.tags

  # The service principal running Terraform must be capacity admin so the
  # Fabric configuration (../fabric) can assign workspaces to the capacity.
  administration_members = setunion([data.azurerm_client_config.current.object_id], var.capacity_admins)

  sku {
    name = lookup(var.capacity_skus, each.key, "F2")
    tier = "Fabric"
  }
}
