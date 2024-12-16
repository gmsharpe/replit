#  #########################
#  ##### CodePipeline #####
#  #######################

# CodePipeline Roles

resource "aws_iam_role" "multi_modal_build_role" {
  assume_role_policy = {
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = [
            "codebuild.amazonaws.com"
          ]
        }
        Action = [
          "sts:AssumeRole"
        ]
      }
    ]
  }
  managed_policy_arns = [
    "arn:aws:iam::aws:policy/AWSCodeBuildAdminAccess"
  ]
  force_detach_policies = [
    {
      PolicyName = "S3PutObject"
      PolicyDocument = {
        Version = "2012-10-17"
        Statement = [
          {
            Effect = "Allow"
            Action = [
              "s3:PutObject",
              "s3:PutObjectAcl"
            ]
            Resource = [
              "arn:aws:s3:::${aws_s3_bucket.multi_modal_code_s3_bucket.id}/*"
            ]
          },
          {
            Effect = "Allow"
            Action = [
              "logs:CreateLogGroup",
              "logs:CreateLogStream",
              "logs:PutLogEvents",
              "logs:PutRetentionPolicy"
            ]
            Resource = "*"
          }
        ]
      }
    }
  ]
}

resource "aws_codebuild_project" "multi_modal_init_codebuild" {
  name = "MultiModalInitCodebuild-${var.environment_name}"
  build_timeout = 10
  source {

    type         = "NO_SOURCE"
    insecure_ssl = false
    buildspec    = <<EOF
version: 0.2
phases:
  pre_build:
    commands:
      - pip3 install awscli --upgrade --user
  build:
    commands:
      - echo Build started on `date`
      - wget https://aws-blogs-artifacts-public.s3.amazonaws.com/ML-16564/enterprise_search.zip
      - unzip enterprise_search.zip
      - ls -al
      - aws s3 cp . s3://${aws_s3_bucket.multi_modal_code_s3_bucket.id}/ --recursive --exclude enterprise_search.zip
  post_build:
    commands:
      - echo Build completed on `date`
      - aws s3 cp enterprise_search.zip s3://${aws_s3_bucket.multi_modal_code_s3_bucket.id}/app.zip
EOF
  }
  environment {
    type = "LINUX_CONTAINER"
    image = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
    compute_type = "BUILD_GENERAL1_SMALL"
  }
  service_role = aws_iam_role.multi_modal_build_role.arn
  artifacts {
    type = "NO_ARTIFACTS"
  }
}

resource "aws_iam_role" "multi_modal_build_custom_resource_role" {
  name = "MultiModalInitCodebuild-ResourceRole-${var.environment_name}"
  assume_role_policy = {
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = [
            "lambda.amazonaws.com"
          ]
        }
        Action = [
          "sts:AssumeRole"
        ]
      }
    ]
  }
  path = "/"
  force_detach_policies = [
    {
      PolicyName = "LambdaCustomPolicy"
      PolicyDocument = {
        Version = "2012-10-17"
        Statement = [
          {
            Effect = "Allow"
            Action = [
              "codebuild:StartBuild",
              "codebuild:BatchGetBuilds"
            ]
            Resource = [
              aws_codebuild_project.multi_modal_init_codebuild.arn
            ]
          },
          {
            Effect = "Allow"
            Action = [
              "logs:CreateLogGroup",
              "logs:CreateLogStream",
              "logs:PutLogEvents",
              "logs:PutRetentionPolicy"
            ]
            Resource = "*"
          },
          {
            Effect = "Allow"
            Action = [
              "s3:ListBucket",
              "s3:DeleteObject",
              "s3:DeleteObjectVersion",
              "s3:ListBucketVersions"
            ]
            Resource = [
              "arn:aws:s3:::${aws_s3_bucket.multi_modal_code_s3_bucket.id}/*",
              "arn:aws:s3:::${aws_s3_bucket.multi_modal_code_s3_bucket.id}"
            ]
          }
        ]
      }
    }
  ]
}

resource "aws_lambda_function" "multi_modal_build_custom_resource_function" {
  function_name = "MultiModalInitCodebuild-Function-${var.environment_name}"
  handler       = "index.handler"
  role          = aws_iam_role.multi_modal_build_custom_resource_role.arn
  timeout       = 300
  runtime       = "python3.12"

  source_code_hash = filebase64sha256("build_custom_resource_lambda.zip")

  filename = "build_custom_resource_lambda.zip"

  environment {
    variables = {
      ENVIRONMENT_NAME = var.environment_name
    }
  }
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "build_custom_resource_lambda.py"
  output_path = "build_custom_resource_lambda.zip"
}

# todo

#   MultiModalBuildCustomResource:
#    Type: Custom::BuildCode
#    Properties:
#      ServiceToken: !GetAtt MultiModalBuildCustomResourceFunction.Arn
#      PROJECT: !Ref MultiModalInitCodebuild
#      CODEBUCKET: !Ref MultiModalCodeS3Bucket


######################
##      Cleanup     ##
######################


resource "aws_iam_role" "multi_modal_clean_custom_resource_role" {
  assume_role_policy = {
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = [
            "lambda.amazonaws.com"
          ]
        }
        Action = [
          "sts:AssumeRole"
        ]
      }
    ]
  }
  path = "/"
  managed_policy_arns = [
    // Unable to resolve Fn::GetAtt with value: [
    //   "Infrastructure",
    //   "Outputs.LogsPolicy"
    // ] because 'Fn::GetAtt - Resource "Infrastructure" not found in template.'
  ]
  force_detach_policies = [
    {
      PolicyName = "LambdaCustomPolicy"
      PolicyDocument = {
        Version = "2012-10-17"
        Statement = [
          {
            Effect = "Allow"
            Action = [
              "s3:ListBucket",
              "s3:DeleteObject",
              "s3:DeleteObjectVersion",
              "s3:ListBucketVersions"
            ]
            Resource = [
              "arn:aws:s3:::${aws_s3_bucket.multi_modal_code_s3_bucket.id}/*",
              "arn:aws:s3:::${aws_s3_bucket.multi_modal_code_s3_bucket.id}",
              "arn:aws:s3:::${aws_s3_bucket.multi_modal_artifact_store.id}/*",
              "arn:aws:s3:::${aws_s3_bucket.multi_modal_artifact_store.id}",
              "arn:aws:s3:::${aws_s3_bucket.multi_modal_cloud_trail_bucket.id}/*",
              "arn:aws:s3:::${aws_s3_bucket.multi_modal_cloud_trail_bucket.id}",
              "arn:aws:s3:::${aws_s3_bucket.s3_data_bucket_name.id}/*",
              "arn:aws:s3:::${aws_s3_bucket.s3_data_bucket_name.id}"
            ]
          },
          {
            Effect = "Allow"
            Action = [
              "cloudformation:DeleteStack",
              "cloudformation:DescribeStacks",
              "cloudformation:ListStackResources"
            ]
            Resource = [
              "arn:aws:cloudformation:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:stack/${local.stack_name}-deploy-${var.environment_name}/*",
              "arn:aws:cloudformation:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:stack/${local.stack_name}-data-ingestion-deploy-${var.environment_name}/*"
            ]
          }
        ]
      }
    }
  ]
}

resource "aws_lambda_function" "multi_modal_clean_custom_resource_function" {
  function_name = "MultiModalCleanCustomResourceFunction-${var.environment_name}"
  handler = "index.handler"
  role = aws_iam_role.multi_modal_clean_custom_resource_role.arn
  timeout = 300
  runtime = "python3.12"

  source_code_hash = filebase64sha256("clean_custom_resource_lambda.zip")

  filename = "${path.module}/lambdas/clean_custom_resource_lambda.zip"

  environment {
    variables = {
      ENVIRONMENT_NAME = var.environment_name
    }
  }

}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "clean_custom_resource_lambda.py"
  output_path = "clean_custom_resource_lambda.zip"
}


# todo
#   MultiModalCleanCustomResource:
#    DependsOn: MultiModalCloudformationExecutionRole
#    Type: Custom::BuildCode
#    Properties:
#      ServiceToken: !GetAtt MultiModalCleanCustomResourceFunction.Arn
#      CODEBUCKET: !Ref MultiModalCodeS3Bucket
#      ARTIFACTBUCKET: !Ref MultiModalArtifactStore
#      TRAILBUCKET: !Ref MultiModalCloudTrailBucket
#      DATABUCKET: !Ref S3DataBucketName
