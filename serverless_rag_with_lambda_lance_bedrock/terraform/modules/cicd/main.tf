data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# resource "aws_ssm_parameter" "github_oauth_token" {
#   name  = "/github/replit/oauth_token"
#   type  = "SecureString"
#   value = var.github_oauth_token
# }

resource "aws_s3_bucket" "artifact_bucket" {
  bucket = "${var.stack_name}-artifacts-${data.aws_region.current.name}-${data.aws_caller_identity.current.account_id}"
}

resource "aws_codestarconnections_connection" "github_connection" {
  name          = "${var.github_repo}-github-repo"
  provider_type = "GitHub"
}

resource "aws_iam_policy" "codebuild_policy" {
  name        = "codebuild-policy"
  description = "Policy for CodeBuild to access S3, CloudWatch, and logs"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:GetBucketLocation"
        ]
        Resource = [
          aws_s3_bucket.artifact_bucket.arn,
          "${aws_s3_bucket.artifact_bucket.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/codebuild/*"
      },
      {
        Effect = "Allow"
        Action = [
          "codebuild:StartBuild",
          "codebuild:BatchGetBuilds"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role" "codebuild_role" {
  name = "codebuild-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "codebuild.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "codebuild_custom_policy" {
  role       = aws_iam_role.codebuild_role.name
  policy_arn = aws_iam_policy.codebuild_policy.arn
}

locals {
  build_spec_nodejs = <<-EOT
version: 0.2

phases:
  install:
    runtime-versions:
      nodejs: latest

  pre_build:
    commands:
      - echo "Current working directory:"
      - pwd
      - cd ${var.lambda_source_path}
      - echo "Installing dependencies..."
      - npm install

  build:
    commands:
      - echo "Checking if required files exist..."
      - if [ -f package.json ]; then echo "package.json exists"; else echo "package.json missing!"; exit 1; fi
      - if [ -d node_modules ]; then echo "node_modules exists"; else echo "node_modules missing!"; exit 1; fi
      - echo "Zipping Lambda function (including .mjs files)..."
      - zip -r lambda_function.zip . -i '*.mjs' node_modules package.json

  post_build:
    commands:
      - echo "Uploading artifact to S3..."
      - aws s3 cp lambda_function.zip s3://${aws_s3_bucket.artifact_bucket.id}/lambda_function.zip --region ${data.aws_region.current.name}

artifacts:
  files:
    - serverless_rag_with_lambda_lance_bedrock/rag_lambda/mjs/lambda_function.zip
EOT

  build_spec_python = <<-EOT
version: 0.2

phases:
  install:
    runtime-versions:
      python: 3.11

  pre_build:
    commands:
      - echo "Current working directory:"
      - pwd
      - cd ${var.lambda_source_path}
      - echo "Installing Python dependencies..."
      - pip install -r requirements.txt -t ./package

  build:
    commands:
      - echo "Checking required files..."
      - if [ -f index.py ]; then echo "index.py exists"; else echo "index.py missing!"; exit 1; fi
      - if [ -d package ]; then echo "Dependencies folder exists"; else echo "Dependencies folder missing!"; exit 1; fi
      - echo "Packaging Lambda function..."
      - cp index.py package/
      - cd package
      - zip -r lambda_function.zip .
      - mv lambda_function.zip ../

  post_build:
    commands:
      - echo "Uploading artifact to S3..."
      - aws s3 cp ../lambda_function.zip s3://${aws_s3_bucket.artifact_bucket.id}/lambda_function.zip --region ${data.aws_region.current.name}

artifacts:
  files:
    - lambda_function.zip
EOT

}

resource "aws_codebuild_project" "document_processor_build" {
  name         = "document-processor-build"
  service_role = aws_iam_role.codebuild_role.arn

  source {
    type      = "GITHUB"
    location  = "https://github.com/${var.github_owner}/${var.github_repo}.git"
    buildspec = local.build_spec_python
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

resource "aws_iam_role" "eventbridge_role" {
  name = "eventbridge-codebuild-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "eventbridge_codebuild_policy" {
  name = "eventbridge-codebuild-policy"
  role = aws_iam_role.eventbridge_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow"
        Action   = "codebuild:StartBuild"
        Resource = aws_codebuild_project.document_processor_build.arn
      }
    ]
  })
}


resource "aws_cloudwatch_event_target" "codebuild_target" {
  rule     = aws_cloudwatch_event_rule.trigger_codebuild.name
  arn      = aws_codebuild_project.document_processor_build.arn
  role_arn = aws_iam_role.eventbridge_role.arn
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

resource "aws_iam_policy" "codepipeline_policy" {
  name        = "codepipeline-policy"
  description = "Policy for CodePipeline to access CodeStar Connections"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow"
        Action   = "codestar-connections:UseConnection"
        Resource = aws_codestarconnections_connection.github_connection.arn
      },
      {
        "Effect" : "Allow",
        "Action" : ["codebuild:StartBuild", "codebuild:BatchGetBuilds"],
        "Resource" : "arn:aws:codebuild:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:project/${aws_codebuild_project.document_processor_build.name}"
      },
      {
        Effect = "Allow",
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket"
        ],
        Resource = [
          aws_s3_bucket.artifact_bucket.arn,
          "${aws_s3_bucket.artifact_bucket.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "codepipeline_policy_attachment" {
  role       = aws_iam_role.codepipeline_role.name
  policy_arn = aws_iam_policy.codepipeline_policy.arn
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
