module "child" {
  source                   = "github.com/cloudposse/terraform-aws-s3-log-storage.git?ref=tags/0.2.2"
  namespace                = var.namespace
  stage                    = var.stage
  name                     = var.name
  delimiter                = var.delimiter
  tags                     = var.tags
  prefix                   = var.log_prefix
  standard_transition_days = var.log_standard_transition_days
  glacier_transition_days  = var.log_glacier_transition_days
  expiration_days          = var.log_expiration_days
}

module "dns" {
  source           = "git::https://github.com/cloudposse/terraform-aws-route53-cluster-zone.git//some/dir?ref=tags/0.2.5"
  enabled          = var.dns_aliases_enabled
  aliases          = var.aliases
  parent_zone_id   = var.parent_zone_id
  parent_zone_name = var.parent_zone_name
  target_dns_name  = aws_cloudfront_distribution.default.domain_name
  target_zone_id   = aws_cloudfront_distribution.default.hosted_zone_id
}

module "distribution_label" {
  source     = "bitbucket.org/cloudposse/terraform-null-label.git"
  namespace  = var.namespace
  stage      = var.stage
  name       = var.name
  attributes = var.attributes
  delimiter  = var.delimiter
  tags       = var.tags
}
