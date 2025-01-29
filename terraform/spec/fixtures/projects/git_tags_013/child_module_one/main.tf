module "child" {
  source                       = "git@github.com:cloudposse/terraform-aws-jenkins.git?ref=tags/0.4.0"
  namespace                    = var.namespace
  stage                        = var.stage
  name                         = var.name
  delimiter                    = var.delimiter
  attributes                   = [compact(concat(var.attributes, ["origin"]))]
  tags                         = var.tags
  availability_zone            = ""
  loadbalancer_certificate_arn = ""
  public_subnets               = []
}

module "distribution_label" {
  source     = "git::https://github.com/cloudposse/terraform-null-label.git"
  namespace  = var.namespace
  stage      = var.stage
  name       = var.name
  attributes = var.attributes
  delimiter  = var.delimiter
  tags       = var.tags
}
