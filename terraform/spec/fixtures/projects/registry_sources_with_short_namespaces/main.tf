terraform {
  required_providers {
    azuredevops = {
      source  = "ni/azuredevops"
      version = "0.4.6"
    }
  }
}

module "httpbin" {
  source  = "aq/httpbin-on-ecs/aws"
  version = "0.0.1"
}
