variable "stack_name" {}
variable "function_name" {}

variable "github_repo" {}
variable "github_owner" {}
variable "github_branch" {}

variable "document_table_name" {}
variable "document_processor_build_name" {
  default = "streaming-rag-document-processor"
}