provider "aws" {
  region = "us-west-2"
}

module "lambda-streaming-rag" {
  source        = "../modules/lambda-streaming-rag"
  stack_name    = var.stack_name
  function_name = var.function_name
  document_table_name = var.document_table_name
  artifact_bucket_id = module.cicd.artifact_bucket_id
  depends_on = [module.cicd]
}

module "cicd" {
  source             = "../modules/cicd"
  stack_name         = var.stack_name
  function_name      = var.function_name
  github_branch      = var.github_branch
  github_oauth_token = var.github_oauth_token
  github_owner       = var.github_owner
  github_repo        = var.github_repo
  lambda_source_path = var.lambda_source_path
}
