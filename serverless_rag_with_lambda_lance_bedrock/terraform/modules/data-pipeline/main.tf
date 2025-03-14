provider "aws" {
  region = "us-west-2"
}


resource "aws_s3_bucket" "document_bucket" {
  bucket = "${var.stack_name}-${data.aws_region.current.name}-${data.aws_caller_identity.current.account_id}"
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
          "AWS" = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/${data.aws_caller_identity.current.user_id}"
        }
        "Action" = "sts:AssumeRole"
      }
    ]
  })
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
        Action   = ["s3:GetObject", "s3:PutObject", "s3:List*"]
        Resource = [
          "arn:aws:s3:::${var.stack_name}-${data.aws_region.current.name}-${data.aws_caller_identity.current.account_id}/*",
          "arn:aws:s3:::${var.stack_name}-${data.aws_region.current.name}-${data.aws_caller_identity.current.account_id}"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "document_processor_attachment" {
  role       = aws_iam_role.document_processor_role.name
  policy_arn = aws_iam_policy.document_processor_policy.arn
}

resource "null_resource" "build_lambda" {
  provisioner "local-exec" {
    command = <<EOT
      cd function && npm install && npm run build && cd ..
      zip -r deployment_package.zip function/
    EOT
  }
}

resource "aws_lambda_function" "document_processor_function" {
  function_name    = "document-processor"
  role            = aws_iam_role.document_processor_role.arn
  runtime         = "nodejs18.x"
  handler         = "function/index.handler"
  timeout         = 900
  memory_size     = 512
  architectures   = ["x86_64"]
  filename        = "./deployment_package.zip" # Ensure your deployment package is properly created

  environment {
    variables = {
      s3BucketName = aws_s3_bucket.document_bucket.id
      region       = data.aws_region.current.name
      lanceDbTable = "doc_table"
    }
  }

  depends_on = [null_resource.build_lambda]
}

resource "aws_s3_bucket_notification" "document_upload_notification" {
  bucket = aws_s3_bucket.document_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.document_processor_function.arn
    events             = ["s3:ObjectCreated:*"]
    filter_prefix      = "documents/"
  }
}

resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.document_processor_function.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.document_bucket.arn
}

data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

