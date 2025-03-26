data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

# data "aws_s3_object" "lambda_zip" {
#   bucket = var.artifact_bucket_id
#   key    = "lambda_function.zip"
#   depends_on = [null_resource.trigger_codebuild]
# }


# Zip the Python directory structure required by Lambda layers
data "archive_file" "layer_zip" {
  type        = "zip"
  source_dir  = "${path.module}/empty_layer_src/"
  output_path = "${path.module}/lambda_layer.zip"
}

# Upload zipped layer to S3
resource "aws_s3_object" "layer_zip_upload" {
  bucket = aws_s3_bucket.artifact_bucket.id
  key    = "lambda_layer/lambda_layer.zip"
  source = data.archive_file.layer_zip.output_path
  etag   = filemd5(data.archive_file.layer_zip.output_path)
}

# Lambda Layer from S3
resource "aws_lambda_layer_version" "empty_layer" {
  layer_name          = "document_processor_layer"
  s3_bucket           = aws_s3_bucket.artifact_bucket.id
  s3_key              = aws_s3_object.layer_zip_upload.key
  compatible_runtimes = ["python3.11"]
  source_code_hash    = data.archive_file.layer_zip.output_base64sha256
}

# resource "aws_lambda_layer_version" "lambda_dependencies" {
#   layer_name          = "lambda_dependencies_layer"
#   s3_bucket           = aws_s3_bucket.artifact_bucket.id
#   s3_key              = "lambda_layer.zip"
#   compatible_runtimes = ["python3.11"]
# }

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/empty_lambda_src/index.py" #local_file.lambda_placeholder.filename
  output_path = "${path.module}/lambda_function.zip"
}

# Upload zip to S3
resource "aws_s3_object" "lambda_zip_upload" {
  bucket = aws_s3_bucket.artifact_bucket.id
  key    = "lambda_function/lambda_function.zip"
  source = data.archive_file.lambda_zip.output_path
  etag   = filemd5(data.archive_file.lambda_zip.output_path)
  depends_on = [data.archive_file.lambda_zip]
}

resource "aws_lambda_function" "document_processor_function" {
  function_name = var.function_name
  role          = aws_iam_role.document_processor_role.arn
  runtime       = "python3.11"
  handler       = "index.handler"
  package_type  = "Zip"
  timeout       = 900
  memory_size   = 1024
  architectures = ["x86_64"]

  s3_bucket = aws_s3_bucket.artifact_bucket.id
  s3_key    = aws_s3_object.lambda_zip_upload.key

  # layers = [
  #   aws_lambda_layer_version.lambda_dependencies.arn
  # ]

  environment {
    variables = {
      s3BucketName = aws_s3_bucket.document_bucket.id
      region       = data.aws_region.current.name
      lanceDbTable = var.document_table_name
    }
  }

  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  lifecycle {
    ignore_changes = [source_code_hash]
  }

  depends_on = [aws_s3_object.lambda_zip_upload]

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