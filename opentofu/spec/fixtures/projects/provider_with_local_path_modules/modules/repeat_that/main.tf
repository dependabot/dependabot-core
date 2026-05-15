resource "azurerm_resource_group" "that" {
  name     = "that-is-a-resource-group"
  location = "westeurope"

  tags = {
    "environment" = "lab"
  }
}
