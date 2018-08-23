module "origin_label" {
  source     = "git::https://github.com/cloudposse/terraform-null-label.git?ref=tags/0.3.7"
  namespace  = "${var.namespace}"
  stage      = "${var.stage}"
  name       = "${var.name}"
  delimiter  = "${var.delimiter}"
  attributes = ["${compact(concat(var.attributes, list("origin")))}"]
  tags       = "${var.tags}"
}

resource "aws_cloudfront_origin_access_identity" "default" {
  comment = "${module.distribution_label.id}"
}

module "logs" {
  source                   = "github.com/cloudposse/terraform-log-storage.git?ref=tags/0.2.2"
  namespace                = "${var.namespace}"
  stage                    = "${var.stage}"
  name                     = "${var.name}"
  delimiter                = "${var.delimiter}"
  attributes               = ["${compact(concat(var.attributes, list("origin", "logs")))}"]
  tags                     = "${var.tags}"
  prefix                   = "${var.log_prefix}"
  standard_transition_days = "${var.log_standard_transition_days}"
  glacier_transition_days  = "${var.log_glacier_transition_days}"
  expiration_days          = "${var.log_expiration_days}"
}

module "distribution_label" {
  source     = "bitbucket.org/cloudposse/terraform-null-label.git"
  namespace  = "${var.namespace}"
  stage      = "${var.stage}"
  name       = "${var.name}"
  attributes = "${var.attributes}"
  delimiter  = "${var.delimiter}"
  tags       = "${var.tags}"
}

resource "aws_cloudfront_distribution" "default" {
  enabled             = "${var.enabled}"
  is_ipv6_enabled     = "${var.is_ipv6_enabled}"
  comment             = "${var.comment}"
  default_root_object = "${var.default_root_object}"
  price_class         = "${var.price_class}"

  logging_config = {
    include_cookies = "${var.log_include_cookies}"
    bucket          = "${module.logs.bucket_domain_name}"
    prefix          = "${var.log_prefix}"
  }

  aliases = ["${var.aliases}"]

  custom_error_response = ["${var.custom_error_response}"]

  origin {
    domain_name = "${var.origin_domain_name}"
    origin_id   = "${module.distribution_label.id}"
    origin_path = "${var.origin_path}"

    custom_origin_config {
      http_port                = "${var.origin_http_port}"
      https_port               = "${var.origin_https_port}"
      origin_protocol_policy   = "${var.origin_protocol_policy}"
      origin_ssl_protocols     = "${var.origin_ssl_protocols}"
      origin_keepalive_timeout = "${var.origin_keepalive_timeout}"
      origin_read_timeout      = "${var.origin_read_timeout}"
    }
  }

  viewer_certificate {
    acm_certificate_arn            = "${var.acm_certificate_arn}"
    ssl_support_method             = "sni-only"
    minimum_protocol_version       = "${var.viewer_minimum_protocol_version}"
    cloudfront_default_certificate = "${var.acm_certificate_arn == "" ? true : false}"
  }

  default_cache_behavior {
    allowed_methods  = "${var.allowed_methods}"
    cached_methods   = "${var.cached_methods}"
    target_origin_id = "${module.distribution_label.id}"
    compress         = "${var.compress}"

    forwarded_values {
      headers = ["${var.forward_headers}"]

      query_string = "${var.forward_query_string}"

      cookies {
        forward           = "${var.forward_cookies}"
        whitelisted_names = ["${var.forward_cookies_whitelisted_names}"]
      }
    }

    viewer_protocol_policy = "${var.viewer_protocol_policy}"
    default_ttl            = "${var.default_ttl}"
    min_ttl                = "${var.min_ttl}"
    max_ttl                = "${var.max_ttl}"
  }

  cache_behavior = "${var.cache_behavior}"

  web_acl_id = "${var.web_acl_id}"

  restrictions {
    geo_restriction {
      restriction_type = "${var.geo_restriction_type}"
      locations        = "${var.geo_restriction_locations}"
    }
  }

  tags = "${module.distribution_label.tags}"
}

module "dns" {
  source           = "git::https://github.com/cloudposse/terraform-aws-route53-al.git//some/dir?ref=tags/0.2.5"
  enabled          = "${var.dns_aliases_enabled}"
  aliases          = "${var.aliases}"
  parent_zone_id   = "${var.parent_zone_id}"
  parent_zone_name = "${var.parent_zone_name}"
  target_dns_name  = "${aws_cloudfront_distribution.default.domain_name}"
  target_zone_id   = "${aws_cloudfront_distribution.default.hosted_zone_id}"
}
