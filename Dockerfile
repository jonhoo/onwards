# See https://github.com/jonhoo/onwards/issues/14
# and https://beeb.li/blog/aws-lambda-rust-docker
FROM public.ecr.aws/lambda/provided:al2023

COPY target/lambda/lambda/bootstrap ${LAMBDA_RUNTIME_DIR}/bootstrap

# Gain equivalent of the lambda function layer
#
#   arn:aws:lambda:${data.aws_region.current.region}:580247275435:layer:LambdaInsightsExtension-Arm64:5
#
# See https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Lambda-Insights-Getting-Started-docker.html
RUN curl -O https://lambda-insights-extension-arm64.s3-ap-northeast-1.amazonaws.com/amazon_linux/lambda-insights-extension-arm64.rpm && \
    rpm -U lambda-insights-extension-arm64.rpm && \
    rm -f lambda-insights-extension-arm64.rpm

ENV RUST_LOG="info,tower_http=debug,onwards_api=trace"
CMD ["app.handler"]
