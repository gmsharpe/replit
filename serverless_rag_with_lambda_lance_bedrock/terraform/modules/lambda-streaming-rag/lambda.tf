data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

# data "aws_s3_object" "lambda_zip" {
#   bucket = var.artifact_bucket_id
#   key    = "lambda_function.zip"
#   depends_on = [null_resource.trigger_codebuild]
# }

resource "null_resource" "trigger_codebuild" {
  provisioner "local-exec" {
    command = <<EOF
    build_id=$(aws codebuild start-build --project-name ${var.document_processor_build_name} --query 'build.id' --output text)
    aws codebuild batch-get-builds --ids $build_id --query 'builds[0].buildStatus' --output text
    status="IN_PROGRESS"
    while [ "$status" == "IN_PROGRESS" ]; do
      echo "Waiting for CodeBuild job completion..."
      sleep 10
      status=$(aws codebuild batch-get-builds --ids $build_id --query 'builds[0].buildStatus' --output text)
    done

    if [ "$status" != "SUCCEEDED" ]; then
      echo "CodeBuild failed with status: $status"
      exit 1
    fi
    EOF
  }
}

resource "aws_lambda_layer_version" "lambda_dependencies" {
  layer_name          = "lambda_dependencies_layer"
  s3_bucket           = aws_s3_bucket.artifact_bucket.id
  s3_key              = "lambda_layer.zip"
  compatible_runtimes = ["python3.11"]
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
  s3_key    = "lambda_function.zip"

  layers = [
    aws_lambda_layer_version.lambda_dependencies.arn
  ]

  environment {
    variables = {
      s3BucketName = aws_s3_bucket.document_bucket.id
      region       = data.aws_region.current.name
      lanceDbTable = var.document_table_name
    }
  }

  depends_on = [null_resource.trigger_codebuild]
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