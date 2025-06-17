# https://github.com/hashicorp/terraform-dynamic-credentials-setup-examples/tree/main/aws

variable "tfc_aws_audience" {
  type        = string
  default     = "aws.workload.identity"
  description = "The audience value to use in run identity tokens"
}

variable "tfc_hostname" {
  type        = string
  default     = "app.terraform.io"
  description = "The hostname of the TFC or TFE instance you'd like to use with AWS"
}

variable "tfc_organization_name" {
  type        = string
  description = "The name of your Terraform Cloud organization"
}

variable "tfc_project_name" {
  type        = string
  default     = "Default Project"
  description = "The project under which a workspace will be created"
}

variable "tfc_workspace_name" {
  type        = string
  default     = "onwards"
  description = "The name of the workspace that you'd like to create and connect to AWS"
}

# Data source used to grab the TLS certificate for Terraform Cloud.
#
# https://registry.terraform.io/providers/hashicorp/tls/latest/docs/data-sources/certificate
data "tls_certificate" "tfc_certificate" {
  url = "https://${var.tfc_hostname}"
}

# Creates an OIDC provider which is restricted to
#
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_openid_connect_provider
resource "aws_iam_openid_connect_provider" "tfc_provider" {
  url             = data.tls_certificate.tfc_certificate.url
  client_id_list  = [var.tfc_aws_audience]
  thumbprint_list = [data.tls_certificate.tfc_certificate.certificates[0].sha1_fingerprint]
}

# Creates a role which can only be used by the specified Terraform
# cloud workspace.
#
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role
data "aws_iam_policy_document" "tfc_plan_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.tfc_provider.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.tfc_hostname}:aud"
      values   = ["${one(aws_iam_openid_connect_provider.tfc_provider.client_id_list)}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.tfc_hostname}:sub"
      values   = ["organization:${var.tfc_organization_name}:project:${var.tfc_project_name}:workspace:${var.tfc_workspace_name}:run_phase:plan"]
    }
  }
}
resource "aws_iam_role" "tfc_plan" {
  name               = "tfc-plan-role"
  assume_role_policy = data.aws_iam_policy_document.tfc_plan_assume.json

  inline_policy {
    name   = "planning-permits"
    policy = data.aws_iam_policy_document.tfc_plan_policy.json
  }
}
data "aws_iam_policy_document" "tfc_apply_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.tfc_provider.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.tfc_hostname}:aud"
      values   = ["${one(aws_iam_openid_connect_provider.tfc_provider.client_id_list)}"]
    }

    condition {
      test     = "StringLike"
      variable = "${var.tfc_hostname}:sub"
      values   = ["organization:${var.tfc_organization_name}:project:${var.tfc_project_name}:workspace:${var.tfc_workspace_name}:run_phase:*"]
    }
  }
}
resource "aws_iam_role" "tfc_apply" {
  name               = "tfc-apply-role"
  assume_role_policy = data.aws_iam_policy_document.tfc_apply_assume.json

  inline_policy {
    name   = "apply-permits"
    policy = data.aws_iam_policy_document.tfc_apply_policy.json
  }
}

# Creates a policy that will be used to define the permissions that
# the previously created role has within AWS.
#
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy
data "aws_iam_policy_document" "tfc_plan_policy" {
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
data "aws_iam_policy_document" "tfc_apply_policy" {
  statement {
    actions   = ["*"]
    resources = ["*"]
  }
}

# Runs in this workspace will be automatically authenticated
# to AWS with the permissions set in the AWS policy.
#
# https://registry.terraform.io/providers/hashicorp/tfe/latest/docs/resources/workspace
resource "tfe_workspace" "onwards" {
  name         = var.tfc_workspace_name
  organization = var.tfc_organization_name

  file_triggers_enabled = false
  queue_all_runs        = false
  working_directory     = "infra"
}
