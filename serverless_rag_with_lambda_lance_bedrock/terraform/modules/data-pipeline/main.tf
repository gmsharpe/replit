provider "aws" {
  region = "us-west-2"
}

data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

