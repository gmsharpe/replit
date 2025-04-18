provider "aws" {
  region = "us-west-2"
}

module "document-processor-image" {
  source                        = "../modules/document-processor-image"
  stack_name                    = var.stack_name
  function_name                 = var.function_name
  document_table_name           = var.document_table_name
  github_branch                 = var.github_branch
  github_owner                  = var.github_owner
  github_repo                   = var.github_repo
  document_processor_build_name = "streaming-rag-document-processor"
}

module "lambda-streaming-rag" {
  source                            = "../modules/lambda-streaming-rag"
  stack_name                        = var.stack_name
  function_name                     = var.function_name
  document_table_name               = var.document_table_name
  github_branch                     = var.github_branch
  github_owner                      = var.github_owner
  github_repo                       = var.github_repo
  document_processor_repository_url = module.document-processor-image.document_processor_repository_url
  depends_on = [
    module.document-processor-image
  ]
}

// backend to s3

resource "aws_s3_bucket" "tf_state" {
  bucket = "edumore-replit-736682772784"
}

resource "aws_s3_bucket_public_access_block" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

terraform {
  backend "s3" {
    bucket = "edumore-replit-736682772784"
    key    = "serverless_rag_with_lambda_lance_bedrock/terraform.tfstate"
    region = "us-west-2"
  }
}


