# https://github.com/hashicorp/terraform-dynamic-credentials-setup-examples/tree/main/aws

variable "idp_audience" {
  type        = string
  default     = "sts.amazonaws.com"
  description = "The audience value to use in run identity tokens"
}

variable "github_idp" {
  type        = string
  default     = "token.actions.githubusercontent.com"
  description = "The hostname of the GitHub identity provider you'd like to use with AWS"
}

variable "github_repo" {
  type        = string
  description = "The GitHub project of this deployment of onwards"
}

variable "github_apply_branch" {
  type        = string
  default     = "main"
  description = "The GitHub branch that is allowed to run apply"
}

# Data source used to grab the TLS certificate for Terraform Cloud.
#
# https://registry.terraform.io/providers/hashicorp/tls/latest/docs/data-sources/certificate
data "tls_certificate" "gh_idp_certificate" {
  url = "https://${var.github_idp}"
}

# Creates an OIDC provider which is restricted to GitHub
#
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_openid_connect_provider
resource "aws_iam_openid_connect_provider" "gh_provider" {
  url             = data.tls_certificate.gh_idp_certificate.url
  client_id_list  = [var.idp_audience]
  thumbprint_list = [data.tls_certificate.gh_idp_certificate.certificates[0].sha1_fingerprint]
}

# Creates a role which can only be used by the specified Terraform
# cloud workspace.
#
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role
data "aws_iam_policy_document" "tf_plan_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.gh_provider.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.github_idp}:aud"
      values   = ["${one(aws_iam_openid_connect_provider.gh_provider.client_id_list)}"]
    }

    condition {
      test     = "StringLike"
      variable = "${var.github_idp}:sub"
      values   = ["repo: *:ref:refs/heads/*"]
    }
  }
}
resource "aws_iam_role" "tf_plan_role" {
  name               = "tf-plan-role"
  assume_role_policy = data.aws_iam_policy_document.tf_plan_assume.json

  inline_policy {
    name   = "planning-permits"
    policy = data.aws_iam_policy_document.tf_plan_policy.json
  }
}
data "aws_iam_policy_document" "tf_apply_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.gh_provider.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.github_idp}:aud"
      values   = ["${one(aws_iam_openid_connect_provider.gh_provider.client_id_list)}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.github_idp}:sub"
      values   = ["repo: ${var.github_repo}:ref:refs/heads/${var.github_apply_branch}"]
    }
  }
}
resource "aws_iam_role" "tf_apply_role" {
  name               = "tf-apply-role"
  assume_role_policy = data.aws_iam_policy_document.tf_apply_assume.json

  inline_policy {
    name   = "apply-permits"
    policy = data.aws_iam_policy_document.tf_apply_policy.json
  }
}

# Creates a policy that will be used to define the permissions that
# the previously created role has within AWS.
#
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy
data "aws_iam_policy_document" "tf_plan_policy" {
  statement {
    actions = [
      "acm:ListCertificates",
      "cloudfront:GetOriginAccessControl",
      "cloudfront:ListCachePolicies",
      "cloudfront:ListDistributions",
      "cloudfront:ListFunctions",
      "cloudfront:ListOriginAccessControls",
      "cloudwatch:ListDashboards",
      "logs:ListTagsLogGroup",
      "s3:ListAllMyBuckets",
      "sts:GetCallerIdentity",
    ]
    resources = ["*"]
  }
  statement {
    actions   = ["apigateway:GET"]
    resources = ["*"]
  }
  statement {
    actions   = ["acm:DescribeCertificate", "acm:ListTagsForCertificate"]
    resources = [aws_acm_certificate.onwards.arn]
  }
  statement {
    actions = ["logs:DescribeLogGroups"]
    resources = [
      # no per-resource access for this endpoint
      # https://docs.aws.amazon.com/AmazonCloudWatchLogs/latest/APIReference/API_DescribeLogGroups.html
      # aws_cloudwatch_log_group.lambda.arn,
      # aws_cloudwatch_log_group.apigw.arn
      "*"
    ]
  }
  statement {
    actions = ["cloudfront:GetDistribution", "cloudfront:ListTagsForResource"]
    resources = [
      aws_cloudfront_distribution.onwards.arn
    ]
  }
  statement {
    actions = ["cloudfront:GetCachePolicy", "cloudfront:GetCachePolicyConfig"]
    resources = [
      "arn:aws:cloudfront::${data.aws_caller_identity.current.account_id}:cache-policy/${aws_cloudfront_cache_policy.cache_when_requested.id}"
    ]
  }
  statement {
    actions   = ["cloudwatch:GetDashboard"]
    resources = [aws_cloudwatch_dashboard.onwards.dashboard_arn]
  }
  statement {
    actions = ["route53:GetHostedZone", "route53:ListTagsForResource", "route53:ListResourceRecordSets"]
    resources = [
      aws_route53_zone.onwards.arn
    ]
  }
  statement {
    actions   = ["iam:List*", "iam:Get*"]
    resources = ["*"]
  }
  statement {
    actions   = ["lambda:GetFunctionCodeSigningConfig", "lambda:ListVersionsByFunction", "lambda:GetFunction", "lambda:GetPolicy"]
    resources = [aws_lambda_function.onwards.arn]
  }
  statement {
    actions = ["s3:Get*", "s3:ListBucket"]
    resources = [
      aws_s3_bucket.logs.arn,
      "${aws_s3_bucket.logs.arn}/*",
    ]
  }
}
data "aws_iam_policy_document" "tf_apply_policy" {
  statement {
    actions   = ["*"]
    resources = ["*"]
  }
}
