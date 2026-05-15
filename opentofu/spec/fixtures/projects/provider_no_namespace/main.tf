terraform {
  required_version = ">= 1.6"

  required_providers {
    cloudfoundry = {
      source  = "cloudfoundry-community/cloudfoundry"
      version = ">= 0.14.2"
    }
    random = {
      source  = "random"
      version = "2.2.1"
    }
  }
}
