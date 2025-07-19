data "aws_iam_policy_document" "xray" {
  statement {
    actions = [
      "xray:PutTraceSegments",
      "xray:PutTelemetryRecords",
    ]
    resources = ["*"]
  }
}

data "aws_iam_policy_document" "cloudwatch" {
  statement {
    actions = [
      "logs:CreateLogGroup",
    ]
    resources = [aws_cloudwatch_log_group.lambda.arn]
  }

  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["${aws_cloudwatch_log_group.lambda.arn}:*"]
  }
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "onwards" {
  name               = "onwards-api"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
  path               = "/service-role/"
}

resource "aws_iam_role_policy" "xray" {
  name   = "xray"
  role   = aws_iam_role.onwards.id
  policy = data.aws_iam_policy_document.xray.json
}

resource "aws_iam_role_policy" "cloudwatch" {
  name   = "cloudwatch"
  role   = aws_iam_role.onwards.id
  policy = data.aws_iam_policy_document.cloudwatch.json
}

resource "aws_iam_role_policies_exclusive" "onwards_api_inline_policies" {
  role_name    = aws_iam_role.onwards.name
  policy_names = [aws_iam_role_policy.xray.name, aws_iam_role_policy.cloudwatch.name]
}

resource "aws_iam_role_policy_attachments_exclusive" "onwards_api_attached_policies" {
  role_name   = aws_iam_role.onwards.name
  policy_arns = ["arn:aws:iam::aws:policy/CloudWatchLambdaInsightsExecutionRolePolicy"]
}

data "aws_iam_policy_document" "ecr" {
  statement {
    actions = [
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:ListImages"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "onwards-ecr" {
  name   = "ecr"
  role   = aws_iam_role.onwards.id
  policy = data.aws_iam_policy_document.ecr.json
}

resource "aws_ecr_repository" "onwards" {
  name                 = "onwards"
  image_tag_mutability = "IMMUTABLE"
  encryption_configuration {
    encryption_type = "KMS"
  }
}

data "aws_ecr_lifecycle_policy_document" "onwards" {
  rule {
    priority    = 1
    description = "Keep last 5 images"

    selection {
      tag_status      = "any"
      count_type      = "imageCountMoreThan"
      count_number    = 5
    }
  }
}

resource "aws_ecr_lifecycle_policy" "name" {
  repository = aws_ecr_repository.onwards.name
  policy = data.aws_ecr_lifecycle_policy_document.onwards.json
}

variable "lambda_image_tag" {
  type        = string
  description = "The ECR image tag for the lambda's container image"
}

resource "aws_lambda_function" "onwards" {
  function_name = "onwards-api"
  role          = aws_iam_role.onwards.arn
  architectures = ["arm64"]
  package_type  = "Image"
  image_uri     = "${aws_ecr_repository.onwards.repository_url}:${var.lambda_image_tag}"
  timeout       = 30

  image_config {
    entry_point = ["/lambda-entrypoint.sh"]
    command     = ["app.handler"]
  }

  depends_on = [
    aws_cloudwatch_log_group.lambda,
  ]
}
