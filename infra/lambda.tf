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

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/CloudWatchLambdaInsightsExecutionRolePolicy"
  ]
  inline_policy {
    name   = "xray"
    policy = data.aws_iam_policy_document.xray.json
  }
  inline_policy {
    name   = "cloudwatch"
    policy = data.aws_iam_policy_document.cloudwatch.json
  }
}

// To build for AWS Lambda runtime, run:
// ```console
// $ cargo lambda build --release --arm64
// ```
// The artifact will be located in <project_root>/target/lambda/lambda/bootstrap,
check "lambda-built" {
  assert {
    condition     = fileexists("${path.module}/../target/lambda/lambda/bootstrap")
    error_message = "Run `cargo lambda build --release --arm64`"
  }
}

data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.module}/../target/lambda/lambda/bootstrap"
  output_path = "lambda_function_payload.zip"
}

resource "aws_lambda_function" "onwards" {
  function_name = "onwards-api"
  role          = aws_iam_role.onwards.arn
  handler       = "bootstrap"
  runtime       = "provided.al2023"
  architectures = ["arm64"]
  timeout       = 30
  layers = [
    "arn:aws:lambda:${data.aws_region.current.name}:580247275435:layer:LambdaInsightsExtension-Arm64:5"
  ]

  filename         = "lambda_function_payload.zip"
  source_code_hash = data.archive_file.lambda.output_base64sha256

  environment {
    variables = {
      RUST_LOG = "info,tower_http=debug,onwards_api=trace"
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.lambda,
  ]
}
