module "origin_label" {
  source     = "git::https://github.com/cloudposse/terraform-null-label.git?ref=tags/0.4.1"
  namespace  = var.namespace
  stage      = var.stage
  name       = var.name
  delimiter  = var.delimiter
  attributes = [compact(concat(var.attributes, ["origin"]))]
  tags       = var.tags
}
