resource "aws_s3_bucket" "artifact_bucket" {
  bucket = "${var.stack_name}-artifacts-${data.aws_region.current.name}-${data.aws_caller_identity.current.account_id}"
}

resource "aws_codestarconnections_connection" "github_connection" {
  name          = "${var.github_repo}-github-repo"
  provider_type = "GitHub"
}

resource "aws_ecr_repository" "document_processor" {
  name = "${var.stack_name}-document-processor"
}

locals {
  build_spec_container_lambda = <<-EOT
version: 0.2

phases:
  pre_build:
    commands:
      - echo Logging in to Amazon ECR...
      - aws --version
      - REPOSITORY_URI=${aws_ecr_repository.document_processor.repository_url}
      - IMAGE_TAG=latest
      - aws ecr get-login-password --region ${data.aws_region.current.name} | docker login --username AWS --password-stdin $REPOSITORY_URI

  build:
    commands:
      - echo Build started on `date`
      - cd serverless_rag_with_lambda_lance_bedrock/rag_lambda/python
      - echo "index.py contents"
      - cat index.py
      - echo Building the Docker image...
      - docker build -t $REPOSITORY_URI:$IMAGE_TAG .
      - docker tag $REPOSITORY_URI:$IMAGE_TAG $REPOSITORY_URI:$IMAGE_TAG

  post_build:
    commands:
      - echo Build completed on `date`
      - echo Pushing the Docker image...
      - docker push $REPOSITORY_URI:$IMAGE_TAG
      - echo Writing image definitions file...
      - printf '[{"name":"document-processor","imageUri":"%s"}]' $REPOSITORY_URI:$IMAGE_TAG > imagedefinitions.json
      - mv imagedefinitions.json $CODEBUILD_SRC_DIR/imagedefinitions.json

artifacts:
  files:
    - imagedefinitions.json

EOT
}

resource "aws_codebuild_project" "lambda_image_build" {
  name         = "document-processor-container-build"
  service_role = aws_iam_role.codebuild_role.arn

  source {
    type      = "CODEPIPELINE"
    buildspec = local.build_spec_container_lambda
  }

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type    = "BUILD_GENERAL1_MEDIUM"
    image           = "aws/codebuild/standard:5.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = true
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
    source      = ["aws.codepipeline"],
    detail-type = ["CodePipeline Pipeline Execution State Change"],
    detail = {
      state    = ["STARTED"]
      pipeline = [aws_codepipeline.document_processor_pipeline.name]
    }
  })
}

resource "aws_cloudwatch_event_target" "codebuild_target" {
  rule     = aws_cloudwatch_event_rule.trigger_codebuild.name
  arn      = aws_codebuild_project.lambda_image_build.arn
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
    name = "BuildContainerImage"
    action {
      name             = "BuildImage"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["SourceArtifact"]
      output_artifacts = ["ImageArtifact"]
      configuration = {
        ProjectName = aws_codebuild_project.lambda_image_build.name
      }
    }
  }

}
