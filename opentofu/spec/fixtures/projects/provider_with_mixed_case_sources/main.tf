terraform {
  required_version = "~>0.14"

  required_providers {
    confluentcloud = {
      source  = "mongey/confluentcloud"
      version = ">= 0.0.6, < 0.0.12"
    }
  }
}
