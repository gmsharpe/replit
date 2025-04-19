data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

resource "aws_lambda_function_url" "this" {
  function_name = aws_lambda_function.document_processor_function.function_name
  authorization_type = "AWS_IAM"
  invoke_mode = "RESPONSE_STREAM"
}

resource "aws_lambda_function" "document_processor_function" {
  function_name = var.function_name
  role          = aws_iam_role.document_processor_role.arn
  image_uri     = "${var.document_processor_repository_url}:latest"
  package_type  = "Image"
  timeout       = 900
  memory_size   = 1024
  architectures = ["x86_64"]

  environment {
    variables = {
      s3BucketName = aws_s3_bucket.document_bucket.id
      region       = data.aws_region.current.name
      lanceDbTable = var.document_table_name
      AWS_LWA_INVOKE_MODE = "RESPONSE_STREAM"
    }
  }

  lifecycle {
    ignore_changes = [image_uri]
  }
}

resource "aws_s3_bucket" "document_bucket" {
  #bucket = "${var.stack_name}-documents-${data.aws_region.current.name}-${data.aws_caller_identity.current.account_id}"
  bucket = "streaming-rag-on-lambda-documents-us-west-2-736682772784"
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_iam_role" "document_processor_role" {
  name = "document-processor-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
      {
        "Effect" = "Allow"
        "Principal" = {
          "AWS" = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/gmsharpe"
        }
        "Action" = "sts:AssumeRole"
      }
    ]
  })
}
