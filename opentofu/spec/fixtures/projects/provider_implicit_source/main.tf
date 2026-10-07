terraform {
  required_version = ">= 0.12"

  required_providers {
    http = {
      source = "hashicorp/http"
      version = "2.0.0"
    }

    oci = { // When no `source` is specified, use the implied `hashicorp/oci` source address
      version = "3.27"
    }
  }
}
