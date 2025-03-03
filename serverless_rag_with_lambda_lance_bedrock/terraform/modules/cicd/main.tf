data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# data "aws_ssm_parameter" "github_oauth_token" {
#   name  = "/github/oauth_token"
#   with_decryption = true
# }

resource "aws_s3_bucket" "artifact_bucket" {
  bucket = "${var.stack_name}-artifacts-${data.aws_region.current.name}-${data.aws_caller_identity.current.account_id}"
}

resource "aws_iam_role" "codepipeline_role" {
  name = "codepipeline-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "codepipeline.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_codebuild_project" "document_processor_build" {
  name         = "document-processor-build"
  service_role = aws_iam_role.codepipeline_role.arn

  source {
    type     = "GITHUB"
    location = "https://github.com/${var.github_owner}/${var.github_repo}.git"
    buildspec = <<-EOT
version: 0.2

phases:
  install:
    runtime-versions:
      nodejs: latest
  pre_build:
    commands:
      - echo "Navigating to Lambda function directory..."
      - cd ${var.lambda_source_path}
      - echo "Installing dependencies..."
      - npm install
  build:
    commands:
      - echo "Zipping Lambda function (including .mjs files)..."
      - zip -r lambda_function.zip *.mjs node_modules package.json
  post_build:
    commands:
      - echo "Uploading artifact to S3..."
      - aws s3 cp lambda_function.zip s3://${aws_s3_bucket.artifact_bucket.id}/lambda_function.zip --region ${data.aws_region.current.name}
artifacts:
  files:
    - lambda_function.zip
EOT

  }

  artifacts {
    type     = "S3"
    location = aws_s3_bucket.artifact_bucket.id
  }

  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/standard:5.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = true
  }
}


resource "aws_codepipeline" "document_processor_pipeline" {
  name     = "document-processor-pipeline"
  role_arn = aws_iam_role.codepipeline_role.arn

  artifact_store {
    location = aws_s3_bucket.artifact_bucket.id
    type     = "S3"
  }

  stage {
    name = "Source"
    action {
      name     = "GitHubSource"
      category = "Source"
      owner    = "ThirdParty"
      provider = "GitHub"
      version  = "1"
      configuration = {
        Owner      = var.github_owner
        Repo       = var.github_repo
        Branch     = var.github_branch
#        OAuthToken = data.aws_ssm_parameter.github_oauth_token.value

      }
      output_artifacts = ["SourceArtifact"]
    }
  }

  stage {
    name = "Build"
    action {
      name     = "CodeBuild"
      category = "Build"
      owner    = "AWS"
      provider = "CodeBuild"
      version  = "1"
      input_artifacts = ["SourceArtifact"]
      output_artifacts = ["BuildArtifact"]
      configuration = {
        ProjectName = aws_codebuild_project.document_processor_build.name
      }
    }
  }

  stage {
    name = "Deploy"
    action {
      name     = "DeployLambda"
      category = "Deploy"
      owner    = "AWS"
      provider = "Lambda"
      version  = "1"
      input_artifacts = ["BuildArtifact"]
      configuration = {
        FunctionName = var.function_name
        S3Bucket     = aws_s3_bucket.artifact_bucket.id
        S3Key        = "lambda_function.zip"
      }
    }
  }
}