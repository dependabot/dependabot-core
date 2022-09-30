module "s3-webapp-first" {
  source  = "app.terraform.io/example-org-5d3190/s3-webapp/aws"
  version = "0.11.0"
}

module "s3-webapp-second" {
  source  = "app.terraform.io/example-org-5d3190/s3-webapp/aws"
  version = "0.9.1"
}
