provider "azurerm" {
  features {}
  skip_provider_registration = true
}

terraform {
  required_version = "~> 1.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 2.48.0, < 2.65.0"
    }
  }
  backend "azurerm" {
  }
}
