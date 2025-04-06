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
      python: 3.12

  build:
    commands:
      - |
        echo "Starting Lambda Layer build for environment: $${LAYER_NAME}"
        CURRENT_HASH=$(sha256sum serverless_rag_with_lambda_lance_bedrock/rag_lambda/python/$${LAYER_NAME}_layer_requirements.txt | cut -d' ' -f1)
        aws s3 cp s3://${aws_s3_bucket.artifact_bucket.id}/$${LAYER_NAME}_lambda_layer/requirements_hash.txt previous_hash.txt || echo "No previous hash found"
        PREVIOUS_HASH=$(cat previous_hash.txt || echo "")

        echo "Current hash: $CURRENT_HASH"
        echo "Previous hash: $PREVIOUS_HASH"

        if [ "$CURRENT_HASH" != "$PREVIOUS_HASH" ]; then
          echo "Requirements changed, building lambda layer for $${LAYER_NAME}."
          echo "The requirements are: $(cat serverless_rag_with_lambda_lance_bedrock/rag_lambda/python/$${LAYER_NAME}_layer_requirements.txt)"

          python3.12 -m venv create_layer
          source create_layer/bin/activate

          echo "Installing requirements for $${LAYER_NAME} using 'serverless_rag_with_lambda_lance_bedrock/rag_lambda/python/$${LAYER_NAME}_layer_requirements.txt'"
          pip install -r serverless_rag_with_lambda_lance_bedrock/rag_lambda/python/$${LAYER_NAME}_layer_requirements.txt --platform manylinux2014_x86_64 --only-binary=:all: --target ./create_layer/lib/python3.12/site-packages
          # Remove any folder that starts with 'boto3' or 'botocore' in the target directory
          find ./create_layer/lib/python3.12/site-packages -maxdepth 1 -type d -name 'boto3*' -exec rm -rf {} +
          find ./create_layer/lib/python3.12/site-packages -maxdepth 1 -type d -name 'botocore*' -exec rm -rf {} +

          mkdir -p python
          cp -r create_layer/lib python/

          zip -r lambda_layer_$${LAYER_NAME}.zip python
          echo "Uploading lambda layer zip to S3 (S3 bucket: ${aws_s3_bucket.artifact_bucket.id}, S3 key: $${LAYER_NAME}_lambda_layer/lambda_layer.zip)"
          aws s3 cp lambda_layer_$${LAYER_NAME}.zip s3://${aws_s3_bucket.artifact_bucket.id}/$${LAYER_NAME}_lambda_layer/lambda_layer.zip --region ${data.aws_region.current.name}

          echo "Publishing new Lambda Layer version..."
          LAYER_VERSION_ARN=$(aws lambda publish-layer-version \
            --layer-name $${LAYER_NAME} \
            --content S3Bucket=${aws_s3_bucket.artifact_bucket.id},S3Key=$${LAYER_NAME}_lambda_layer/lambda_layer.zip \
            --compatible-runtimes python3.12 \
            --query 'LayerVersionArn' \
            --output text)

          echo "New layer version published: $LAYER_VERSION_ARN"

          echo "Updating Lambda function to use the latest layer..."
          aws lambda update-function-configuration \
            --function-name $LAMBDA_NAME \
            --layers $LAYER_VERSION_ARN

          echo "$CURRENT_HASH" > requirements_hash.txt
          aws s3 cp requirements_hash.txt s3://${aws_s3_bucket.artifact_bucket.id}/$${LAYER_NAME}/requirements_hash.txt

        else
          echo "No changes in requirements for $${LAYER_NAME}, skipping lambda layer build."
        fi

artifacts:
  files: []

cache:
  paths:
    - '/root/.cache/pip/**/*'
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

  deploy_lambda_build_spec = <<-EOT
version: 0.2

phases:
  build:
    commands:
      - aws lambda update-function-code --function-name ${var.function_name} --s3-bucket ${aws_s3_bucket.artifact_bucket.id} --s3-key ${aws_s3_object.lambda_zip_upload.key}
EOT

}

resource "aws_codebuild_project" "langchain_lambda_layer_build" {
  name         = "langchain-lambda-layer-build"
  service_role = aws_iam_role.codebuild_role.arn

  source {
    type      = "GITHUB"
    location  = "https://github.com/${var.github_owner}/${var.github_repo}.git"
    buildspec = local.build_spec_layer_artifact
  }

  artifacts {
    type     = "S3"
    location = aws_s3_bucket.artifact_bucket.id
    name = "langchain_lambda_layer"

  }

  cache {
    type = "S3"
    location = "${aws_s3_bucket.artifact_bucket.id}/langchain/lambda_layer_cache"
  }

  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/standard:5.0"
    type            = "LINUX_CONTAINER"

    environment_variable {
      name  = "LAYER_NAME"
      value = "langchain"
    }
  }
}

resource "aws_codebuild_project" "lancedb_lambda_layer_build" {
  name         = "lancedb-lambda-layer-build"
  service_role = aws_iam_role.codebuild_role.arn

  source {
    type      = "GITHUB"
    location  = "https://github.com/${var.github_owner}/${var.github_repo}.git"
    buildspec = local.build_spec_layer_artifact
  }

  artifacts {
    type     = "S3"
    location = aws_s3_bucket.artifact_bucket.id
    name = "lancedb_lambda_layer"
  }

  cache {
    type = "S3"
    location = "${aws_s3_bucket.artifact_bucket.id}/lancedb/lambda_layer_cache"
  }

  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/standard:5.0"
    type            = "LINUX_CONTAINER"

    environment_variable {
      name  = "LAYER_NAME"
      value = "lancedb"
    }
  }
}

resource "aws_codebuild_project" "lambda_function_deploy" {
  name         = "lambda-function-deploy"
  service_role = aws_iam_role.codebuild_role.arn

  source {
    type      = "GITHUB"
    location  = "https://github.com/${var.github_owner}/${var.github_repo}.git"
    buildspec = local.deploy_lambda_build_spec
  }

  artifacts {
    type     = "NO_ARTIFACTS"
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
    name = "BuildLangchainLambdaLayer"
    action {
      name     = "CodeBuild"
      category = "Build"
      owner    = "AWS"
      provider = "CodeBuild"
      version  = "1"
      input_artifacts = ["SourceArtifact"]
      output_artifacts = ["LangchainLambdaLayerBuildArtifact"]
      configuration = {
        ProjectName = aws_codebuild_project.langchain_lambda_layer_build.name
      }
    }
  }

  stage {
    name = "BuildLanceDBLambdaLayer"
    action {
      name     = "CodeBuild"
      category = "Build"
      owner    = "AWS"
      provider = "CodeBuild"
      version  = "1"
      input_artifacts = ["SourceArtifact"]
      output_artifacts = ["LanceDBLambdaLayerBuildArtifact"]
      configuration = {
        ProjectName = aws_codebuild_project.lancedb_lambda_layer_build.name
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

  stage {
    name = "DeployLambdaFunction"
    action {
      name     = "CodeBuild"
      category = "Build"
      owner    = "AWS"
      provider = "CodeBuild"
      version  = "1"
      input_artifacts = ["SourceArtifact"]
      configuration = {
        ProjectName = aws_codebuild_project.lambda_function_deploy.name
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
