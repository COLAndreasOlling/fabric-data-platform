output "capacities" {
  description = "Capacity names to use as capacity_name in ../fabric."
  value = {
    for key, c in azurerm_fabric_capacity.this : key => {
      id   = c.id
      name = c.name
    }
  }
}
