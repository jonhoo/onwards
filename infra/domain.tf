locals {
  domain = "r4r.fyi"
}

resource "aws_route53_zone" "onwards" {
  name = local.domain
}

resource "aws_route53_record" "onwards_mx" {
  zone_id = aws_route53_zone.onwards.zone_id
  name    = local.domain
  type    = "MX"
  ttl     = 3600
  records = [
    "10 mx1.improvmx.com",
    "20 mx2.improvmx.com"
  ]
}

resource "aws_route53_record" "onwards_spf" {
  zone_id = aws_route53_zone.onwards.zone_id
  name    = local.domain
  type    = "TXT"
  ttl     = 3600
  records = [
    "v=spf1 include:spf.improvmx.com ~all",
  ]
}

resource "aws_route53_record" "onwards_cf" {
  zone_id = aws_route53_zone.onwards.zone_id
  name    = local.domain
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.onwards.domain_name
    zone_id                = aws_cloudfront_distribution.onwards.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "onwards_cf_v6" {
  zone_id = aws_route53_zone.onwards.zone_id
  name    = local.domain
  type    = "AAAA"
  alias {
    name                   = aws_cloudfront_distribution.onwards.domain_name
    zone_id                = aws_cloudfront_distribution.onwards.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_acm_certificate" "onwards" {
  provider          = aws.us-east-1
  domain_name       = local.domain
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "onwards_cert" {
  for_each = {
    for dvo in aws_acm_certificate.onwards.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = aws_route53_zone.onwards.zone_id
}

resource "aws_acm_certificate_validation" "onwards" {
  provider                = aws.us-east-1
  certificate_arn         = aws_acm_certificate.onwards.arn
  validation_record_fqdns = [for record in aws_route53_record.onwards_cert : record.fqdn]
}
