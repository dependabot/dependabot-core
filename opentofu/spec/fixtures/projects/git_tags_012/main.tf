module "origin_label" {
  source     = "git::https://github.com/cloudposse/terraform-null-label.git?ref=tags/0.3.7"
  namespace  = var.namespace
  stage      = var.stage
  name       = var.name
  delimiter  = var.delimiter
  attributes = [compact(concat(var.attributes, ["origin"]))]
  tags       = var.tags
}

module "logs" {
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

module "distribution_label" {
  source     = "bitbucket.org/cloudposse/terraform-null-label.git"
  namespace  = var.namespace
  stage      = var.stage
  name       = var.name
  attributes = var.attributes
  delimiter  = var.delimiter
  tags       = var.tags
}

resource "aws_cloudfront_distribution" "default" {
  enabled             = var.enabled
  is_ipv6_enabled     = var.is_ipv6_enabled
  comment             = var.comment
  default_root_object = var.default_root_object
  price_class         = var.price_class
  logging_config {
    include_cookies = var.log_include_cookies
    bucket          = module.logs.bucket_domain_name
    prefix          = var.log_prefix
  }
  # TF-UPGRADE-TODO: In Terraform v0.10 and earlier, it was sometimes necessary to
  # force an interpolation expression to be interpreted as a list by wrapping it
  # in an extra set of list brackets. That form was supported for compatibility in
  # v0.11, but is no longer supported in Terraform v0.12.
  #
  # If the expression in the following list itself returns a list, remove the
  # brackets to avoid interpretation as a list of lists. If the expression
  # returns a single list item then leave it as-is and remove this TODO comment.
  aliases = [var.aliases]
  dynamic "custom_error_response" {
    for_each = [var.custom_error_response]
    content {
      # TF-UPGRADE-TODO: The automatic upgrade tool can't predict
      # which keys might be set in maps assigned here, so it has
      # produced a comprehensive set here. Consider simplifying
      # this after confirming which keys can be set in practice.

      error_caching_min_ttl = lookup(custom_error_response.value, "error_caching_min_ttl", null)
      error_code            = custom_error_response.value.error_code
      response_code         = lookup(custom_error_response.value, "response_code", null)
      response_page_path    = lookup(custom_error_response.value, "response_page_path", null)
    }
  }
  origin {
    domain_name = var.origin_domain_name
    origin_id   = module.distribution_label.id
    origin_path = var.origin_path
    custom_origin_config {
      http_port                = var.origin_http_port
      https_port               = var.origin_https_port
      origin_protocol_policy   = var.origin_protocol_policy
      origin_ssl_protocols     = var.origin_ssl_protocols
      origin_keepalive_timeout = var.origin_keepalive_timeout
      origin_read_timeout      = var.origin_read_timeout
    }
  }
  viewer_certificate {
    acm_certificate_arn            = var.acm_certificate_arn
    ssl_support_method             = "sni-only"
    minimum_protocol_version       = var.viewer_minimum_protocol_version
    cloudfront_default_certificate = var.acm_certificate_arn == "" ? true : false
  }
  default_cache_behavior {
    allowed_methods  = var.allowed_methods
    cached_methods   = var.cached_methods
    target_origin_id = module.distribution_label.id
    compress         = var.compress
    forwarded_values {
      # TF-UPGRADE-TODO: In Terraform v0.10 and earlier, it was sometimes necessary to
      # force an interpolation expression to be interpreted as a list by wrapping it
      # in an extra set of list brackets. That form was supported for compatibility in
      # v0.11, but is no longer supported in Terraform v0.12.
      #
      # If the expression in the following list itself returns a list, remove the
      # brackets to avoid interpretation as a list of lists. If the expression
      # returns a single list item then leave it as-is and remove this TODO comment.
      headers      = [var.forward_headers]
      query_string = var.forward_query_string
      cookies {
        forward = var.forward_cookies
        # TF-UPGRADE-TODO: In Terraform v0.10 and earlier, it was sometimes necessary to
        # force an interpolation expression to be interpreted as a list by wrapping it
        # in an extra set of list brackets. That form was supported for compatibility in
        # v0.11, but is no longer supported in Terraform v0.12.
        #
        # If the expression in the following list itself returns a list, remove the
        # brackets to avoid interpretation as a list of lists. If the expression
        # returns a single list item then leave it as-is and remove this TODO comment.
        whitelisted_names = [var.forward_cookies_whitelisted_names]
      }
    }
    viewer_protocol_policy = var.viewer_protocol_policy
    default_ttl            = var.default_ttl
    min_ttl                = var.min_ttl
    max_ttl                = var.max_ttl
  }
  dynamic "cache_behavior" {
    for_each = var.cache_behavior
    content {
      # TF-UPGRADE-TODO: The automatic upgrade tool can't predict
      # which keys might be set in maps assigned here, so it has
      # produced a comprehensive set here. Consider simplifying
      # this after confirming which keys can be set in practice.

      allowed_methods           = cache_behavior.value.allowed_methods
      cached_methods            = cache_behavior.value.cached_methods
      compress                  = lookup(cache_behavior.value, "compress", null)
      default_ttl               = lookup(cache_behavior.value, "default_ttl", null)
      field_level_encryption_id = lookup(cache_behavior.value, "field_level_encryption_id", null)
      max_ttl                   = lookup(cache_behavior.value, "max_ttl", null)
      min_ttl                   = lookup(cache_behavior.value, "min_ttl", null)
      path_pattern              = cache_behavior.value.path_pattern
      smooth_streaming          = lookup(cache_behavior.value, "smooth_streaming", null)
      target_origin_id          = cache_behavior.value.target_origin_id
      trusted_signers           = lookup(cache_behavior.value, "trusted_signers", null)
      viewer_protocol_policy    = cache_behavior.value.viewer_protocol_policy

      dynamic "forwarded_values" {
        for_each = lookup(cache_behavior.value, "forwarded_values", [])
        content {
          headers                 = lookup(forwarded_values.value, "headers", null)
          query_string            = forwarded_values.value.query_string
          query_string_cache_keys = lookup(forwarded_values.value, "query_string_cache_keys", null)

          dynamic "cookies" {
            for_each = lookup(forwarded_values.value, "cookies", [])
            content {
              forward           = cookies.value.forward
              whitelisted_names = lookup(cookies.value, "whitelisted_names", null)
            }
          }
        }
      }

      dynamic "lambda_function_association" {
        for_each = lookup(cache_behavior.value, "lambda_function_association", [])
        content {
          event_type   = lambda_function_association.value.event_type
          include_body = lookup(lambda_function_association.value, "include_body", null)
          lambda_arn   = lambda_function_association.value.lambda_arn
        }
      }
    }
  }
  web_acl_id = var.web_acl_id
  restrictions {
    geo_restriction {
      restriction_type = var.geo_restriction_type
      locations        = var.geo_restriction_locations
    }
  }
  tags = module.distribution_label.tags
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

module "duplicate_label" {
  source     = "git::https://github.com/cloudposse/terraform-null-label.git?ref=tags/0.3.7"
  namespace  = var.namespace
  stage      = var.stage
  name       = var.name
  delimiter  = var.delimiter
  attributes = [compact(concat(var.attributes, ["origin"]))]
  tags       = var.tags
}

module "github_ssh_without_protocol" {
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
