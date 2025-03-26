resource "aws_s3_bucket" "artifact_bucket" {
  bucket = "${var.stack_name}-artifacts-${data.aws_region.current.name}-${data.aws_caller_identity.current.account_id}"
}

resource "aws_codestarconnections_connection" "github_connection" {
  name          = "${var.github_repo}-github-repo"
  provider_type = "GitHub"
}

locals {

  build_spec_layer_artifact = <<-EOT
version: 0.2

phases:
  install:
    runtime-versions:
      python: 3.11

  build:
    commands:
      - mkdir python
      - pip install -r serverless_rag_with_lambda_lance_bedrock/rag_lambda/python/requirements.txt -t ./python
      - zip -r lambda_layer.zip python

  post_build:
    commands:
      - aws s3 cp lambda_layer.zip s3://${aws_s3_bucket.artifact_bucket.id}/lambda_layer/lambda_layer.zip --region ${data.aws_region.current.name}

artifacts:
  files:
    - lambda_layer.zip
EOT

  build_spec_lambda_function_artifact = <<-EOT
version: 0.2

phases:
  build:
    commands:
      - cp serverless_rag_with_lambda_lance_bedrock/rag_lambda/python/index.py ./
      - zip lambda_function.zip index.py

  post_build:
    commands:
      - aws s3 cp lambda_function.zip s3://${aws_s3_bucket.artifact_bucket.id}/lambda_function/lambda_function.zip --region ${data.aws_region.current.name}

artifacts:
  files:
    - lambda_function.zip
EOT

}

resource "aws_codebuild_project" "lambda_layer_build" {
  name         = "lambda-layer-build"
  service_role = aws_iam_role.codebuild_role.arn

  source {
    type      = "GITHUB"
    location  = "https://github.com/${var.github_owner}/${var.github_repo}.git"
    buildspec = local.build_spec_layer_artifact
  }

  artifacts {
    type     = "S3"
    location = aws_s3_bucket.artifact_bucket.id
    name = "lambda_layer"
  }

  cache {
    type = "S3"
    location = "${aws_s3_bucket.artifact_bucket.id}/lambda_layer_cache"
  }

  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/standard:5.0"
    type            = "LINUX_CONTAINER"
  }
}

resource "aws_codebuild_project" "document_processor_build" {
  name         = "document-processor-build"
  service_role = aws_iam_role.codebuild_role.arn

  source {
    type      = "GITHUB"
    location  = "https://github.com/${var.github_owner}/${var.github_repo}.git"
    buildspec = local.build_spec_lambda_function_artifact
  }

  artifacts {
    type     = "S3"
    location = aws_s3_bucket.artifact_bucket.id
    name = "lambda_function"
  }

  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/standard:5.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = true
    environment_variable {
      name  = "LAMBDA_FUNCTION_NAME"
      value = var.function_name
    }

    environment_variable {
      name  = "S3_BUCKET"
      value = aws_s3_bucket.artifact_bucket.id
    }

    environment_variable {
      name  = "AWS_REGION"
      value = data.aws_region.current.name
    }
  }

}

resource "aws_cloudwatch_event_rule" "trigger_codebuild" {
  name        = "trigger-codebuild-on-pipeline-update"
  description = "Trigger CodeBuild when CodePipeline is updated"

  event_pattern = jsonencode({
    source = ["aws.codepipeline"],
    detail-type = ["CodePipeline Pipeline Execution State Change"],
    detail = {
      state = ["STARTED"]
      pipeline = [aws_codepipeline.document_processor_pipeline.name]
    }
  })
}

resource "aws_cloudwatch_event_target" "codebuild_target" {
  rule     = aws_cloudwatch_event_rule.trigger_codebuild.name
  arn      = aws_codebuild_project.document_processor_build.arn
  role_arn = aws_iam_role.eventbridge_role.arn
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
      owner    = "AWS"
      provider = "CodeStarSourceConnection"
      version  = "1"
      configuration = {
        ConnectionArn    = aws_codestarconnections_connection.github_connection.arn
        FullRepositoryId = "${var.github_owner}/${var.github_repo}"
        BranchName       = var.github_branch
      }
      output_artifacts = ["SourceArtifact"]
    }
  }

  stage {
    name = "BuildLambdaLayer"
    action {
      name     = "CodeBuild"
      category = "Build"
      owner    = "AWS"
      provider = "CodeBuild"
      version  = "1"
      input_artifacts = ["SourceArtifact"]
      output_artifacts = ["LambdaLayerBuildArtifact"]
      configuration = {
        ProjectName = aws_codebuild_project.lambda_layer_build.name
      }
    }
  }

  stage {
    name = "BuildLambdaFunction"
    action {
      name     = "CodeBuild"
      category = "Build"
      owner    = "AWS"
      provider = "CodeBuild"
      version  = "1"
      input_artifacts = ["SourceArtifact"]
      output_artifacts = ["LambdaFunctionBuildArtifact"]
      configuration = {
        ProjectName = aws_codebuild_project.document_processor_build.name
      }
    }
  }

  # stage {
  #   name = "Deploy"
  #   action {
  #     name     = "DeployLambda"
  #     category = "Deploy"
  #     owner    = "AWS"
  #     provider = "Lambda"
  #     version  = "1"
  #     input_artifacts = ["BuildArtifact"]
  #     configuration = {
  #       FunctionName = var.function_name
  #       S3Bucket     = aws_s3_bucket.artifact_bucket.id
  #       S3Key        = "lambda_function.zip"
  #     }
  #   }
  # }
  #depends_on = [aws_ssm_parameter.github_oauth_token]
}
