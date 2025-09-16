resource "azurerm_resource_group" "this" {
  name     = "this-is-a-resource-group"
  location = "northeurope"

  tags = {
    "environment" = "lab"
  }
}
