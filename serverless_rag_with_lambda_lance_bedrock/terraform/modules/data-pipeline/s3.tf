data "aws_s3_bucket" "document_bucket" {
  bucket = "${var.stack_name}-documents-${data.aws_region.current.name}-${data.aws_caller_identity.current.account_id}"
}

data "aws_s3_bucket" "artifact_bucket" {
  bucket = "${var.stack_name}-artifacts-${data.aws_region.current.name}-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_notification" "document_upload_notification" {
  bucket = data.aws_s3_bucket.document_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.document_processor_function.arn
    events = ["s3:ObjectCreated:*"]
    filter_prefix       = "documents/"
  }
}

resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.document_processor_function.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = data.aws_s3_bucket.document_bucket.arn
}
