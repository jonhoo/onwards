resource "aws_apigatewayv2_api" "onwards" {
  name          = "onwards"
  protocol_type = "HTTP"
}

data "aws_iam_policy_document" "apigw_assume" {
  statement {
    principals {
      type        = "Service"
      identifiers = ["apigateway.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "apigw_cw" {
  name               = "onwards-api-gw"
  description        = "Allows API Gateway to push logs to CloudWatch Logs."
  assume_role_policy = data.aws_iam_policy_document.apigw_assume.json
}

resource "aws_iam_role_policy_attachments_exclusive" "apigw_cw_attach" {
  role_name   = aws_iam_role.apigw_cw.name
  policy_arns = ["arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"]
}

resource "aws_api_gateway_account" "onwards" {
  cloudwatch_role_arn = aws_iam_role.apigw_cw.arn
}

resource "aws_apigatewayv2_stage" "onwards" {
  api_id      = aws_apigatewayv2_api.onwards.id
  name        = "$default"
  auto_deploy = true
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.apigw.arn
    format = jsonencode({
      "requestId" : "$context.requestId",
      "ip" : "$context.identity.sourceIp",
      "requestTime" : "$context.requestTime",
      "httpMethod" : "$context.httpMethod",
      "routeKey" : "$context.routeKey",
      "status" : "$context.status",
      "protocol" : "$context.protocol",
      "responseLength" : "$context.responseLength"
    })
  }
  default_route_settings {
    # burst should be set to at most the number of shortlinks you have.
    throttling_burst_limit = 250
    # rate limit should be set quite low -- it's the number of new (and
    # uncached!) shortlinks that can be resolved per second. given that
    # shortlinks are cached for 24h, it would be unreasonable for this to be
    # much more than 10.
    throttling_rate_limit = 20
  }
}

resource "aws_apigatewayv2_integration" "onwards" {
  api_id                 = aws_apigatewayv2_api.onwards.id
  integration_type       = "AWS_PROXY"
  integration_method     = "POST"
  integration_uri        = aws_lambda_function.onwards.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "root" {
  api_id    = aws_apigatewayv2_api.onwards.id
  route_key = "GET /"
  target    = "integrations/${aws_apigatewayv2_integration.onwards.id}"
}

resource "aws_apigatewayv2_route" "forward" {
  api_id    = aws_apigatewayv2_api.onwards.id
  route_key = "GET /{short}"
  target    = "integrations/${aws_apigatewayv2_integration.onwards.id}"
}

resource "aws_lambda_permission" "onwards" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.onwards.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_stage.onwards.execution_arn}/*"
}
