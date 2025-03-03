data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

resource "aws_lambda_function" "document_processor_function" {
  function_name    = var.function_name
  role             = aws_iam_role.document_processor_role.arn
  runtime          = "nodejs18.x"   # Ensure Lambda runtime supports ES Modules
  handler          = "index.handler"  # Ensure this matches the exported function in index.mjs
  package_type     = "Zip"
  timeout          = 900
  memory_size      = 512
  architectures    = ["x86_64"]
  s3_bucket        = var.artifact_bucket_id
  s3_key           = "lambda_function.zip"

  environment {
    variables = {
      s3BucketName = aws_s3_bucket.document_bucket.id
      region       = data.aws_region.current.name
      lanceDbTable = var.document_table_name
    }
  }
}

resource "aws_s3_bucket" "document_bucket" {
  bucket = "${var.stack_name}-documents-${data.aws_region.current.name}-${data.aws_caller_identity.current.account_id}"
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
      }
    ]
  })

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  ]
}
