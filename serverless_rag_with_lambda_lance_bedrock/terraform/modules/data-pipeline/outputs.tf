output "document_processor_function_arn" {
  description = "Lambda Function ARN"
  value       = aws_lambda_function.document_processor_function.arn
}

output "document_processor_function_role" {
  description = "IAM Role for the Document Processor function"
  value       = aws_iam_role.document_processor_role.arn
}

output "document_bucket_name" {
  description = "S3 bucket name for document storage"
  value       = aws_s3_bucket.document_bucket.id
}

output "document_table_name" {
  description = "Name of the Document Table in LanceDB"
  value       = "doc_table"
}

output "deployment_region" {
  description = "AWS Region where the stack is deployed"
  value       = data.aws_region.current.name
}
