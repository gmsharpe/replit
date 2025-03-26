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
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "lambda:CreateFunction",
          "lambda:UpdateFunctionConfiguration",
          "lambda:UpdateFunctionCode",
          "lambda:PublishVersion",
          "lambda:PublishLayerVersion",
          "lambda:GetLayerVersion",
          "lambda:DeleteLayerVersion"
        ],
        "Resource" : "*"
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
        "Resource" : [
          aws_codebuild_project.document_processor_build.arn,
          aws_codebuild_project.lambda_layer_build.arn,
          aws_codebuild_project.lambda_function_deploy.arn

        ]
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