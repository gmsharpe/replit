output "ecr_repository_url" {
  description = "URL of the ECR Repository"
  value       = aws_ecr_repository.document_processor.repository_url
}

output "document_table_name" {
  description = "Name of the Document Table in LanceDB"
  value       = "doc_table"
}

output "deployment_region" {
  description = "AWS Region where the stack is deployed"
  value       = data.aws_region.current.name
}
