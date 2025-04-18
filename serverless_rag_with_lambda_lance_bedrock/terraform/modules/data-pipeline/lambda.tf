resource "aws_lambda_function" "document_processor_function" {
  function_name = "document-processor"
  role          = aws_iam_role.document_processor_role.arn
  runtime       = "python3.12"
  handler       = "index.handler"
  timeout       = 900
  memory_size   = 512
  architectures = ["x86_64"]
  filename      = "./data_pipeline_function.zip"
  s3_bucket     = data.aws_s3_bucket.artifact_bucket.id
  s3_key        = "lambda_functions/data_pipeline_function.zip"

  environment {
    variables = {
      s3BucketName = data.aws_s3_bucket.document_bucket.id
      region       = data.aws_region.current.name
      lanceDbTable = "doc_table"
    }
  }
}