module "duplicate_label" {
  source     = "git::https://github.com/cloudposse/terraform-null-label.git?ref=tags/0.3.7"
  namespace  = "${var.namespace}"
  stage      = "${var.stage}"
  name       = "${var.name}"
  delimiter  = "${var.delimiter}"
  attributes = ["${compact(concat(var.attributes, list("origin")))}"]
  tags       = "${var.tags}"
}
