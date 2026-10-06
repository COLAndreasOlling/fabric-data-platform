output "capacities" {
  description = "Fabric capacities per environment."
  value = {
    for env, c in azurerm_fabric_capacity.this : env => {
      id             = c.id
      name           = c.name
      resource_group = c.resource_group_name
    }
  }
}
