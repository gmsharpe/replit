variable "stack_name" {
  default = "streaming-rag-on-lambda"
}
variable "function_name" {
  default = "streaming-rag-on-lambda"
}
variable "github_oauth_token" {
  default = ""
}
variable "github_repo" {
  default = "replit"
}
variable "github_owner" {
  default = "gmsharpe"
}
variable "github_branch" {
  default = "main"
}
variable "lambda_source_path" {
  default = "replit/serverless_rag_with_lambda_lance_bedrock/rag_lambda/mjs"
}
variable "document_table_name" {
  default = "doc_table"
}