locals {
  gw_origin_id = "onwards-api"
}

resource "aws_cloudfront_cache_policy" "cache_when_requested" {
  name        = "CacheWhenRequested"
  default_ttl = 1
  max_ttl     = 31536000
  min_ttl     = 1
  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config {
      cookie_behavior = "none"
    }
    headers_config {
      header_behavior = "none"
    }
    query_strings_config {
      query_string_behavior = "none"
    }
    enable_accept_encoding_brotli = true
    enable_accept_encoding_gzip   = true
  }
}

resource "aws_cloudfront_distribution" "onwards" {
  origin {
    origin_id = local.gw_origin_id
    # NOTE: this is stupid
    domain_name = "${aws_apigatewayv2_api.onwards.id}.execute-api.${data.aws_region.current.name}.amazonaws.com"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  aliases             = [var.domain]
  price_class         = "PriceClass_All"
  http_version        = "http2"

  logging_config {
    include_cookies = false
    bucket          = aws_s3_bucket.logs.bucket_domain_name
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.gw_origin_id

    compress               = true
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = false

      headers = [
        "Origin",
      ]

      cookies {
        forward = "none"
      }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.onwards.certificate_arn
    minimum_protocol_version = "TLSv1.2_2021"
    ssl_support_method       = "sni-only"
  }
}
