provider "aws" {
  region = "us-west-2"
}

module "lambda-streaming-rag" {
  source        = "../modules/lambda-streaming-rag"
  stack_name    = var.stack_name
  function_name = var.function_name
  ecr_image_uri = module.cicd.ecr_repository_url

}

module "cicd" {
  source     = "../modules/cicd"
  stack_name = var.stack_name
}


data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

