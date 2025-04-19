variable "stack_name" {}
variable "function_name" {}

variable "github_repo" {}
variable "github_owner" {}
variable "github_branch" {}

variable "document_table_name" {}
variable "document_processor_build_name" {
  default = "streaming-rag-document-processor"
}
variable "language" {
  default = "mjs"
}
variable "function_location_dir" {
  default = "serverless_rag_with_lambda_lance_bedrock/rag_lambda/mjs"
}
variable "function_file_name" {
  default = "index.mjs"
}