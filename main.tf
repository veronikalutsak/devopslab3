terraform {
  required_version = ">= 1.5"
  required_providers {
    aws     = { source = "hashicorp/aws", version = "~> 5.0" }
    archive = { source = "hashicorp/archive", version = "~> 2.4" }
  }
}

locals {
  is_local = var.local_endpoint != null
}

provider "aws" {
  region = var.region

  # Для емулятора потрібні фіктивні ключі та пропуск валідацій
  access_key                  = local.is_local ? "test" : null
  secret_key                  = local.is_local ? "test" : null
  skip_credentials_validation = local.is_local
  skip_metadata_api_check     = local.is_local
  skip_requesting_account_id  = local.is_local
  s3_use_path_style           = local.is_local

  endpoints {
    s3         = var.local_endpoint
    lambda     = var.local_endpoint
    apigateway = var.local_endpoint
    iam        = var.local_endpoint
    sts        = var.local_endpoint
  }
}

data "aws_caller_identity" "current" {}

# ---------- S3 ----------
resource "aws_s3_bucket" "data" {
  bucket        = "${var.project}-data-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "data" {
  bucket                  = aws_s3_bucket.data.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_object" "greeting" {
  bucket       = aws_s3_bucket.data.id
  key          = "data/greeting.json"
  content_type = "application/json"
  content = jsonencode({
    message = "Hello from S3 via Lambda and API Gateway!"
  })
}

# ---------- IAM ----------
data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${var.project}-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

resource "aws_iam_role_policy_attachment" "logs" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "s3_read" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.data.arn}/*"]
  }
}

resource "aws_iam_role_policy" "s3_read" {
  name   = "s3-read"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.s3_read.json
}

# ---------- Lambda ----------
data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.module}/lambda/handler.py"
  output_path = "${path.module}/lambda.zip"
}

resource "aws_lambda_function" "api" {
  function_name    = "${var.project}-fn"
  role             = aws_iam_role.lambda.arn
  runtime          = "python3.12"
  handler          = "handler.handler"
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256
  timeout          = 5
  memory_size      = 128

  environment {
    variables = {
      BUCKET      = aws_s3_bucket.data.id
      KEY         = aws_s3_object.greeting.key
      S3_ENDPOINT = coalesce(var.lambda_s3_endpoint, var.local_endpoint, "")
    }
  }
}

# ---------- API Gateway (REST) ----------
resource "aws_api_gateway_rest_api" "api" {
  name = "${var.project}-api"
}

resource "aws_api_gateway_resource" "hello" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "hello"
}

resource "aws_api_gateway_method" "get_hello" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.hello.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.hello.id
  http_method             = aws_api_gateway_method.get_hello.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.api.invoke_arn
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}

resource "aws_api_gateway_deployment" "this" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  triggers = {
    redeploy = sha1(jsonencode([
      aws_api_gateway_resource.hello.id,
      aws_api_gateway_method.get_hello.id,
      aws_api_gateway_integration.lambda.id,
    ]))
  }
  lifecycle { create_before_destroy = true }
  depends_on = [aws_api_gateway_integration.lambda]
}

resource "aws_api_gateway_stage" "prod" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  deployment_id = aws_api_gateway_deployment.this.id
  stage_name    = "prod"
}