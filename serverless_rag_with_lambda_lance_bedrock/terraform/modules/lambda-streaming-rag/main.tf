data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

# data "aws_s3_object" "lambda_zip" {
#   bucket = var.artifact_bucket_id
#   key    = "lambda_function.zip"
# }

resource "null_resource" "trigger_codebuild" {
  provisioner "local-exec" {
    command = "aws codebuild start-build --project-name ${var.document_processor_build_name}"
  }
}

resource "aws_lambda_function" "document_processor_function" {
  function_name = var.function_name
  role          = aws_iam_role.document_processor_role.arn
  runtime = "nodejs20.x"   # Ensure Lambda runtime supports ES Modules
  handler = "index.handler"  # Ensure this matches the exported function in index.mjs
  package_type  = "Zip"
  timeout       = 900
  memory_size   = 1024
  architectures = ["x86_64"]
  s3_bucket     = var.artifact_bucket_id
  s3_key        = "lambda_function.zip"

  environment {
    variables = {
      s3BucketName = aws_s3_bucket.document_bucket.id
      region       = data.aws_region.current.name
      lanceDbTable = var.document_table_name
    }
  }
  depends_on = [null_resource.trigger_codebuild] # Ensures CodeBuild runs first data.aws_s3_object.lambda_zip,
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

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.document_processor_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_policy" "document_processor_policy" {
  name        = "document-processor-policy"
  description = "IAM policy for the Lambda function"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["bedrock:InvokeModel"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:List*","s3:DeleteObject"]
        Resource = [
          "${aws_s3_bucket.document_bucket.arn}/*",
          aws_s3_bucket.document_bucket.arn
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "document_processor_attachment" {
  role       = aws_iam_role.document_processor_role.name
  policy_arn = aws_iam_policy.document_processor_policy.arn
}