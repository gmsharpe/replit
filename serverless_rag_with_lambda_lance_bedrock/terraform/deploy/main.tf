provider "aws" {
  region = "us-west-2"
}

module "lambda-streaming-rag" {
  source                        = "../modules/lambda-streaming-rag"
  stack_name                    = var.stack_name
  function_name                 = var.function_name
  document_table_name           = var.document_table_name
  github_branch      = var.github_branch
  github_owner       = var.github_owner
  github_repo        = var.github_repo
}


