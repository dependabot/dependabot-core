module "parent_one" {
  source     = "./child_module_one"  
}

module "parent_two" {
  source     = "./child_module_one"  
}

module "parent_three" {
  source     = "./child_module_two"  
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

module "dns_dup" {
  source           = "git::https://github.com/cloudposse/terraform-aws-route53-cluster-zone.git//some/dir?ref=tags/0.2.5"
  enabled          = var.dns_aliases_enabled
  aliases          = var.aliases
  parent_zone_id   = var.parent_zone_id
  parent_zone_name = var.parent_zone_name
  target_dns_name  = aws_cloudfront_distribution.default.domain_name
  target_zone_id   = aws_cloudfront_distribution.default.hosted_zone_id
}
