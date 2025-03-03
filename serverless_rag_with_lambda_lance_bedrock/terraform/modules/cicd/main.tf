data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

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
    location = "https://github.com/your-repo/document-processor.git"
  }
  artifacts {
    type = "NO_ARTIFACTS"
  }
  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/standard:5.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = true
    environment_variable {
      name  = "ECR_REPO"
      value = aws_ecr_repository.document_processor.repository_url
    }
  }
}

resource "aws_ecr_repository" "document_processor" {
  name = "document-processor"
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
        Owner      = "your-github-user"
        Repo       = "document-processor"
        Branch     = "main"
        OAuthToken = "your-oauth-token"
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
      }
    }
  }
}