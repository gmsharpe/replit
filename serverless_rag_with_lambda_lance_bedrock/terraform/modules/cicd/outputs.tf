output "artifact_bucket_id" {
    value = aws_s3_bucket.artifact_bucket.id
}
output "document_processor_build_name" {
    value = aws_codebuild_project.document_processor_build.name
}