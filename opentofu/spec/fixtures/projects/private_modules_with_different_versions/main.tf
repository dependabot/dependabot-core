module "s3-webapp-first" {
  source  = "registry.opentofu.org/example-org-5d3190/s3-webapp/aws"
  version = "0.11.0"
}

module "s3-webapp-second" {
  source  = "registry.opentofu.org/example-org-5d3190/s3-webapp/aws"
  version = "0.9.1"
}
