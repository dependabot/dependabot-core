terraform {
  required_providers {
    github = {
      source  = "integrations/github"
      version = "~> 4.4, <= 4.12.0"
    }
  }
  required_version = ">= v0.14"
}
