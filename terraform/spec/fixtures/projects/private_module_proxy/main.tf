terraform {
  required_version = ">= 0.14"
}

module "nsg_rules" {
  source = "http://artifactory.dependabot.com/artifactory/tf-modules/azurerm/terraform-azurerm-nsg-rules.v1.1.0.tar.gz"
}
