// Existing Terraform src code found at /tmp/terraform_src.

locals {
  stack_name = "code_pipeline"
}

data "aws_region" "current" {}

data "aws_caller_identity" "current" {}


resource "aws_iam_role" "multi_modal_app_code_build_execution_role" {
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
    // Unable to resolve Fn::GetAtt with value: [
    //   "Infrastructure",
    //   "Outputs.LogsPolicy"
    // ] because 'Fn::GetAtt - Resource "Infrastructure" not found in template.'
  ]
  force_detach_policies = [
    {
      PolicyName = "CodeBuildPolicy"
      PolicyDocument = {
        Version = "2012-10-17"
        Statement = [
          {
            Effect = "Allow"
            Action = [
              "ecr:GetAuthorizationToken"
            ]
            Resource = [
              "*"
            ]
          },
          {
            Effect = "Allow"
            Action = [
              "ecr:UploadLayerPart",
              "ecr:PutImage",
              "ecr:InitiateLayerUpload",
              "ecr:CompleteLayerUpload",
              "ecr:BatchCheckLayerAvailability"
            ]
            Resource = [
              aws_ecr_repository.multi_modal_app_image_repo.arn
            ]
          },
          {
            Effect = "Allow"
            Action = [
              "s3:GetObject",
              "s3:PutObject"
            ]
            Resource = [
              "arn:aws:s3:::${aws_s3_bucket.multi_modal_artifact_store.id}/*"
            ]
          }
        ]
      }
    }
  ]
}

resource "aws_iam_role" "multi_modal_cloudformation_execution_role" {
  assume_role_policy = {
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "cloudformation.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  }
  managed_policy_arns = [
    // Unable to resolve Fn::GetAtt with value: [
    //   "Infrastructure",
    //   "Outputs.LogsPolicy"
    // ] because 'Fn::GetAtt - Resource "Infrastructure" not found in template.'
  ]
  force_detach_policies = [
    {
      PolicyName = "CloudFormationPolicy"
      PolicyDocument = {
        Version = "2012-10-17"
        Statement = [
          {
            Effect = "Allow"
            Action = [
              "iam:ListRolePolicies",
              "iam:ListAttachedRolePolicies",
              "iam:CreateServiceLinkedRole",
              "iam:CreateRole",
              "iam:GetRolePolicy",
              "iam:GetRole",
              "iam:AttachRolePolicy",
              "iam:PutRolePolicy",
              "iam:DetachRolePolicy",
              "iam:DeleteRole",
              "iam:DeleteRolePolicy",
              "iam:PassRole",
              "sts:AssumeRole"
            ]
            Resource = [
              "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/MultiModalECSExecutionRole-${var.environment_name}",
              "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/MultiModalECSTaskRole-${var.environment_name}",
              "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/ECSCustomRole-${var.environment_name}",
              "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/elasticloadbalancing.amazonaws.com/AWSServiceRoleForElasticLoadBalancing",
              "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/ecs.application-autoscaling.amazonaws.com/AWSServiceRoleForApplicationAutoScaling_ECSService"
            ]
          },
          {
            Effect = "Allow"
            Action = [
              "s3:GetBucketAcl",
              "s3:PutBucketAcl"
            ]
            Resource = [
              "arn:aws:s3:::${// Unable to resolve Fn::GetAtt with value: [
//   "Infrastructure",
//   "Outputs.LoggingBucket"
// ] because 'Fn::GetAtt - Resource "Infrastructure" not found in template.'}",
              "arn:aws:s3:::${// Unable to resolve Fn::GetAtt with value: [
//   "Infrastructure",
//   "Outputs.LoggingBucket"
// ] because 'Fn::GetAtt - Resource "Infrastructure" not found in template.'}/*"
            ]
          },
          {
            Effect = "Allow"
            Action = [
              "ecs:DeregisterTaskDefinition",
              "ecs:RegisterTaskDefinition"
            ]
            Resource = [
              "*"
            ]
          },
          {
            Effect = "Allow"
            Action = [
              "ecs:DescribeClusters",
              "ecs:DescribeServices",
              "ecs:CreateService",
              "ecs:UpdateService",
              "ecs:DeleteService"
            ]
            Resource = [
              "arn:aws:ecs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:cluster/${// Unable to resolve Fn::GetAtt with value: [
//   "Infrastructure",
//   "Outputs.MultiModalCluster"
// ] because 'Fn::GetAtt - Resource "Infrastructure" not found in template.'}",
              "arn:aws:ecs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:service/${// Unable to resolve Fn::GetAtt with value: [
//   "Infrastructure",
//   "Outputs.MultiModalCluster"
// ] because 'Fn::GetAtt - Resource "Infrastructure" not found in template.'}/MultiModalECSService-${var.environment_name}"
            ]
          },
          {
            Effect = "Allow"
            Action = [
              "lambda:GetRuntimeManagementConfig",
              "lambda:GetFunctionCodeSigningConfig",
              "lambda:GetFunction",
              "lambda:CreateFunction",
              "lambda:DeleteFunction",
              "lambda:InvokeFunction"
            ]
            Resource = [
              "arn:aws:lambda:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:function:ECSCustomF-${var.environment_name}"
            ]
          },
          {
            Effect = "Allow"
            Action = [
              "cloudfront:ListDistributions"
            ]
            Resource = [
              "*"
            ]
          },
          {
            Effect = "Allow"
            Action = [
              "cloudfront:CreateDistribution",
              "cloudfront:GetDistribution",
              "cloudfront:DeleteDistribution",
              "cloudfront:UpdateDistribution",
              "cloudfront:TagResource"
            ]
            Resource = [
              "*"
            ]
            Condition = {
              StringEquals = {
                aws : ResourceTag/CloudfrontStreamlitApp =
                "${local.stack_name}-deploy-${var.environment_name}-Cloudfront"
              }
            }
          },
          {
            Effect = "Allow"
            Action = [
              "application-autoscaling:DescribeScalableTargets",
              "application-autoscaling:DescribeScalingPolicies",
              "application-autoscaling:RegisterScalableTarget",
              "application-autoscaling:DeregisterScalableTarget"
            ]
            Resource = [
              "arn:aws:application-autoscaling:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:scalable-target/*"
            ]
          },
          {
            Effect = "Allow"
            Action = [
              "application-autoscaling:PutScalingPolicy",
              "application-autoscaling:DeleteScalingPolicy"
            ]
            Resource = [
              "arn:aws:application-autoscaling:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:scalable-target/*"
            ]
          },
          {
            Effect = "Allow"
            Action = [
              "autoscaling:PutScalingPolicy",
              "autoscaling:DescribeScheduledActions"
            ]
            Resource = [
              "*"
            ]
          },
          {
            Effect = "Allow"
            Action = [
              "wafv2:CreateWebACL"
            ]
            Resource = [
              "*"
            ]
          },
          {
            Effect = "Allow"
            Action = [
              "wafv2:GetWebACL",
              "wafv2:DeleteWebACL",
              "wafv2:ListTagsForResource"
            ]
            Resource = [
              "arn:aws:wafv2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*/webacl/CloudFrontWebACL${var.environment_name}/*"
            ]
          },
          {
            Effect = "Allow"
            Action = [
              "ec2:CreateSecurityGroup",
              "ec2:DescribeSecurityGroups",
              "ec2:CreateTags",
              "ec2:DescribeVpcs",
              "ec2:DescribeInternetGateways",
              "ec2:DescribeAccountAttributes",
              "ec2:DescribeSubnets"
            ]
            Resource = [
              "*"
            ]
          },
          {
            Effect = "Allow"
            Action = [
              "ec2:DeleteSecurityGroup",
              "ec2:RevokeSecurityGroupIngress",
              "ec2:RevokeSecurityGroupEgress",
              "ec2:AuthorizeSecurityGroupIngress",
              "ec2:AuthorizeSecurityGroupEgress"
            ]
            Resource = [
              "*"
            ]
            Condition = {
              StringEquals = {
                aws : ResourceTag/Name = join("-", ["MultiModalAppALBSecurityGroup", var.environment_name
              ])
              }
            }
          },
          {
            Effect = "Allow"
            Action = [
              "ec2:DeleteSecurityGroup",
              "ec2:RevokeSecurityGroupIngress",
              "ec2:RevokeSecurityGroupEgress",
              "ec2:AuthorizeSecurityGroupIngress",
              "ec2:AuthorizeSecurityGroupEgress"
            ]
            Resource = [
              "*"
            ]
            Condition = {
              StringEquals = {
                aws : ResourceTag/Name = join("-", ["MultiModalAppContainerSecurityGroup", var.environment_name
              ])
              }
            }
          },
          {
            Effect = "Allow"
            Action = [
              "elasticloadbalancing:DeleteLoadBalancer",
              "elasticloadbalancing:DeleteListener",
              "elasticloadbalancing:DeleteRule",
              "elasticloadbalancing:DeleteTargetGroup"
            ]
            Resource = [
              "arn:aws:elasticloadbalancing:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:targetgroup/MultiModalAppContainerTG-${var.environment_name}/*",
              "arn:aws:elasticloadbalancing:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:loadbalancer/app/MultiModalAppALB-${var.environment_name}/*",
              "arn:aws:elasticloadbalancing:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:listener/app/MultiModalAppALB-${var.environment_name}/*/*",
              "arn:aws:elasticloadbalancing:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:listener-rule/app/MultiModalAppALB-${var.environment_name}/*/*/*"
            ]
          },
          {
            Effect = "Allow"
            Action = [
              "elasticloadbalancing:CreateLoadBalancer",
              "elasticloadbalancing:CreateListener",
              "elasticloadbalancing:CreateRule",
              "elasticloadbalancing:CreateTargetGroup",
              "elasticloadbalancing:DescribeTargetGroups",
              "elasticloadbalancing:DescribeListeners",
              "elasticloadbalancing:DescribeLoadBalancers",
              "elasticloadbalancing:DescribeRules",
              "elasticloadbalancing:ModifyLoadBalancerAttributes",
              "elasticloadbalancing:ModifyTargetGroup",
              "elasticloadbalancing:ModifyTargetGroupAttributes"
            ]
            Resource = [
              "*"
            ]
          },
          {
            Effect = "Allow"
            Action = [
              "iam:CreateServiceLinkedRole",
              "iam:AttachRolePolicy",
              "iam:PutRolePolicy",
              "sts:AssumeRole"
            ]
            Resource = [
              "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/ecs.application-autoscaling.amazonaws.com/AWSServiceRoleForApplicationAutoScaling_ECSService"
            ]
          },
          {
            Effect = "Allow"
            Action = [
              "s3:GetObject",
              "s3:PutObject",
              "s3:List*"
            ]
            Resource = [
              "arn:aws:s3:::${aws_s3_bucket.multi_modal_code_s3_bucket.id}/*",
              "arn:aws:s3:::${aws_s3_bucket.multi_modal_code_s3_bucket.id}",
              "arn:aws:s3:::${aws_s3_bucket.multi_modal_artifact_store.id}/*",
              "arn:aws:s3:::${aws_s3_bucket.multi_modal_artifact_store.id}"
            ]
          },
          {
            Effect = "Allow"
            Action = [
              "iam:UpdateAssumeRolePolicy",
              "iam:ListRoles",
              "iam:ListRolePolicies",
              "iam:ListAttachedRolePolicies",
              "iam:GetRolePolicy",
              "iam:GetRole",
              "iam:PassRole",
              "iam:CreateRole",
              "iam:AttachRolePolicy",
              "iam:PutRolePolicy",
              "iam:DeleteRolePolicy",
              "iam:DeleteRole",
              "iam:UpdateRole",
              "iam:DetachRolePolicy",
              "iam:TagRole"
            ]
            Resource = [
              "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/*"
            ]
          },
          {
            Effect = "Allow"
            Action = [
              "iam:CreatePolicy",
              "iam:DeletePolicy",
              "iam:UpdatePolicy",
              "iam:CreatePolicyVersion",
              "iam:DeletePolicyVersion",
              "iam:GetPolicyVersion",
              "iam:ListPolicyVersions",
              "iam:GetPolicy",
              "iam:ListPolicies",
              "iam:UpdateAssumeRolePolicy"
            ]
            Resource = [
              "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/*"
            ]
          },
          {
            Effect = "Allow"
            Action = [
              "lambda:GetRuntimeManagementConfig",
              "lambda:GetFunctionCodeSigningConfig",
              "lambda:UpdateFunctionConfiguration",
              "lambda:GetFunction",
              "lambda:CreateFunction",
              "lambda:UpdateFunction",
              "lambda:UpdateFunctionCode",
              "lambda:DeleteFunction",
              "lambda:InvokeFunction",
              "lambda:TagResource",
              "lambda:ListTags"
            ]
            Resource = [
              "arn:aws:lambda:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:function:*"
            ]
          },
          {
            Effect = "Allow"
            Action = [
              "lambda:PublishLayerVersion",
              "lambda:GetLayerVersion"
            ]
            Resource = [
              "arn:aws:lambda:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:layer:*"
            ]
          },
          {
            Effect = "Allow"
            Action = [
              "states:CreateStateMachine",
              "states:UpdateStateMachine",
              "states:DeleteStateMachine",
              "states:TagResource",
              "states:ListTagsForResource",
              "states:DescribeStateMachine"
            ]
            Resource = [
              "arn:aws:states:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:stateMachine:*"
            ]
          },
          {
            Effect = "Allow"
            Action = [
              "events:DescribeRule",
              "events:PutRule",
              "events:DeleteRule",
              "events:PutTargets",
              "events:RemoveTargets"
            ]
            Resource = [
              "arn:aws:events:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:rule/*"
            ]
          },
          {
            Effect = "Allow"
            Action = [
              "scheduler:GetSchedule",
              "scheduler:CreateSchedule",
              "scheduler:UpdateSchedule",
              "scheduler:DeleteSchedule",
              "scheduler:GetScheduleGroup",
              "scheduler:CreateScheduleGroup",
              "scheduler:UpdateScheduleGroup",
              "scheduler:DeleteScheduleGroup",
              "scheduler:TagResource",
              "scheduler:UntagResource",
              "scheduler:Get*",
              "scheduler:List*",
              "scheduler:Describe*"
            ]
            Resource = [
              "arn:aws:scheduler:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:schedule/default/*"
            ]
          },
          {
            Effect = "Allow"
            Action = [
              "ssm:GetParameters",
              "ssm:GetParameter"
            ]
            Resource = [
              "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter/multimodalapp/*"
            ]
          },
          {
            Effect = "Allow"
            Action = [
              "ec2:CreateSecurityGroup",
              "ec2:DescribeSecurityGroups",
              "ec2:CreateTags",
              "ec2:DescribeVpcs",
              "ec2:DescribeInternetGateways",
              "ec2:DescribeAccountAttributes",
              "ec2:DescribeSubnets"
            ]
            Resource = [
              "*"
            ]
          },
          {
            Effect = "Allow"
            Action = [
              "ec2:DeleteSecurityGroup",
              "ec2:RevokeSecurityGroupIngress",
              "ec2:RevokeSecurityGroupEgress",
              "ec2:AuthorizeSecurityGroupIngress",
              "ec2:AuthorizeSecurityGroupEgress"
            ]
            Resource = [
              "*"
            ]
            Condition = {
              StringEquals = {
                aws : ResourceTag/Name = [
                "IngestLambdaSecurityGroup-${var.environment_name}",
                "NeptuneDBSecurityGroup-${var.environment_name}"
              ]
              }
            }
          },
          {
            Effect = "Allow"
            Action = [
              "iam:CreateServiceLinkedRole",
              "iam:AttachRolePolicy",
              "iam:PutRolePolicy",
              "sts:AssumeRole"
            ]
            Resource = [
              "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/ecs.application-autoscaling.amazonaws.com/AWSServiceRoleForApplicationAutoScaling_ECSService"
            ]
          },
          {
            Effect = "Allow"
            Action = [
              "cloudformation:UpdateStack",
              "cloudformation:DescribeStacks",
              "cloudformation:CreateStack",
              "cloudformation:CreateChangeSet"
            ]
            Resource = "arn:aws:cloudformation:${data.aws_region.current.name}:aws:transform/Serverless-*"
          },
          {
            Effect = "Allow"
            Action = [
              "logs:DeleteLogGroup"
            ]
            Resource = [
              "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:${local.stack_name}*"
            ]
          }
        ]
      }
    }
  ]
}

resource "aws_iam_role" "multi_modal_step_function_code_build_role" {
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
    // Unable to resolve Fn::GetAtt with value: [
    //   "Infrastructure",
    //   "Outputs.LogsPolicy"
    // ] because 'Fn::GetAtt - Resource "Infrastructure" not found in template.'
  ]
  force_detach_policies = [
    {
      PolicyName = "CodeBuildPolicy"
      PolicyDocument = {
        Version = "2012-10-17"
        Statement = [
          {
            Effect = "Allow"
            Action = [
              "ecr:GetAuthorizationToken"
            ]
            Resource = [
              "*"
            ]
          },
          {
            Effect = "Allow"
            Action = [
              "s3:GetObject",
              "s3:PutObject"
            ]
            Resource = [
              "arn:aws:s3:::${aws_s3_bucket.multi_modal_code_s3_bucket.id}/*",
              "arn:aws:s3:::${aws_s3_bucket.multi_modal_code_s3_bucket.id}",
              "arn:aws:s3:::${aws_s3_bucket.multi_modal_artifact_store.id}/*",
              "arn:aws:s3:::${aws_s3_bucket.multi_modal_artifact_store.id}"
            ]
          },
          {
            Effect = "Allow"
            Action = [
              "cloudformation:UpdateStack",
              "cloudformation:DescribeStacks",
              "cloudformation:CreateStack",
              "cloudformation:CreateChangeSet"
            ]
            Resource = [
              "arn:aws:cloudformation:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:stack/aws-sam-cli-managed-default/*"
            ]
          }
        ]
      }
    }
  ]
}

resource "aws_iam_role" "multi_modal_code_pipeline_service_role" {
  assume_role_policy = {
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = [
            "codepipeline.amazonaws.com"
          ]
        }
        Action = "sts:AssumeRole"
      }
    ]
  }
  path = "/"
  force_detach_policies = [
    {
      PolicyName = "AWS-CodePipeline-Service-3"
      PolicyDocument = {
        Version = "2012-10-17"
        Statement = [
          {
            Effect = "Allow"
            Action = [
              "codebuild:BatchGetBuilds",
              "codebuild:StartBuild"
            ]
            Resource = [
              aws_codebuild_project.multi_modal_app_code_build.arn,
              aws_codebuild_project.multi_modal_step_function_code_build.arn
            ]
          },
          {
            Effect = "Allow"
            Action = [
              "lambda:InvokeFunction",
              "lambda:ListFunctions"
            ]
            Resource = aws_lambda_function.invalidate_cache_function.arn
          },
          {
            Effect = "Allow"
            Action = [
              "iam:PassRole"
            ]
            Resource = aws_iam_role.multi_modal_cloudformation_execution_role.arn
          },
          {
            Effect = "Allow"
            Action = [
              "cloudformation:UpdateStack",
              "cloudformation:DescribeStacks",
              "cloudformation:CreateStack",
              "cloudformation:CreateChangeSet"
            ]
            Resource = join("", [
              "arn:aws:cloudformation:", data.aws_region.current.name, ":", data.aws_caller_identity.current.account_id,
              ":stack/", local.stack_name, "-deploy-", var.environment_name, "/*"
            ])
          },
          {
            Effect = "Allow"
            Action = [
              "cloudformation:UpdateStack",
              "cloudformation:DescribeStacks",
              "cloudformation:CreateStack",
              "cloudformation:CreateChangeSet"
            ]
            Resource = join("", [
              "arn:aws:cloudformation:", data.aws_region.current.name, ":", data.aws_caller_identity.current.account_id,
              ":stack/", local.stack_name, "-data-ingestion-deploy-", var.environment_name, "/*"
            ])
          },
          {
            Effect = "Allow"
            Action = [
              "s3:Get*",
              "s3:List*",
              "s3:Put*"
            ]
            Resource = [
              join("", ["arn:aws:s3:::", aws_s3_bucket.multi_modal_code_s3_bucket.id, "/*"]),
              join("", ["arn:aws:s3:::", aws_s3_bucket.multi_modal_code_s3_bucket.id]),
              join("", ["arn:aws:s3:::", aws_s3_bucket.multi_modal_artifact_store.id, "/*"]),
              join("", ["arn:aws:s3:::", aws_s3_bucket.multi_modal_artifact_store.id])
            ]
          }
        ]
      }
    }
  ]
}

resource "aws_codebuild_project" "multi_modal_step_function_code_build" {
  name = join("-", ["MultiModalStepFunctionCodeBuild", var.environment_name])
  description   = "CodeBuild for Code Pipeline"
  build_timeout = 10
  cache {
    location = "LOCAL"
    modes = [
      "LOCAL_SOURCE_CACHE",
      "LOCAL_DOCKER_LAYER_CACHE"
    ]
    type = "LOCAL"
  }
  artifacts {
    type = "CODEPIPELINE"
  }
  source {
    type      = "CODEPIPELINE"
    buildspec = <<EOF
version: 0.2
phases:
  install:
    runtime-versions:
      python: 3.12
    commands:
      - pip3 install aws-sam-cli
  pre_build:
    commands:
      - sam --version
      - cd src/sam_deploy
  build:
    commands:
      - sam build --template-file template.yaml
      - sam package --template-file template.yaml --s3-bucket ${aws_s3_bucket.multi_modal_code_s3_bucket.id} --output-template-file packaged.yaml
      - ls -al
  artifacts:
    type: zip
    files:
    - src/sam_deploy/packaged.yaml
EOF
  }
  environment {
    type         = "LINUX_CONTAINER"
    image        = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
    compute_type = "BUILD_GENERAL1_SMALL"
  }
  service_role = aws_iam_role.multi_modal_step_function_code_build_role.arn
}

resource "aws_codebuild_project" "multi_modal_app_code_build" {
  name = join("-", ["MultiModalCodeAppBuild", var.environment_name])
  description = "CodeBuild for Code Pipeline"
  cache {
    location = "LOCAL"
    modes = [
      "LOCAL_SOURCE_CACHE",
      "LOCAL_DOCKER_LAYER_CACHE"
    ]
    type = "LOCAL"
  }
  artifacts {
    type = "CODEPIPELINE"
  }
  source {
    type      = "CODEPIPELINE"
    buildspec = <<EOF
version: 0.2
phases :
  pre_build:
    commands :
      - pip3 install
      - aws ecr get-login-password --region ${data.aws_region.current.name} | docker login --username AWS --password-stdin ${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com
      - COMMIT_HASH = $$(echo $CODEBUILD_RESOLVED_SOURCE_VERSION | cut -c 1-7)
      - COMMIT_HASH = $${!COMMIT_HASH//./a}
      - IMAGE_TAG = $${!COMMIT_HASH:=latest}
  build :
    commands :
      - echo Build started on `date`
      - echo $PWD
      - ls -al
      - cd src/webapp/
      - printf '\n' >> Dockerfile
      - printf 'ENTRYPOINT ["streamlit", "run", "app.py", "--server.port=${var.container_port}", "--", "--environmentName", "${var.environment_name}", "--codeS3Bucket", "${aws_s3_bucket.multi_modal_code_s3_bucket.id}"]' >> Dockerfile
      - cat Dockerfile
      - docker build -t ${aws_ecr_repository.multi_modal_app_image_repo.arn} .
      - docker tag ${aws_ecr_repository.multi_modal_app_image_repo.arn}: latest ${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com/${aws_ecr_repository.multi_modal_app_image_repo.arn}: $IMAGE_TAG
  post_build :
    commands :
      - echo Build completed on `date`
      - docker push ${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com/${aws_ecr_repository.multi_modal_app_image_repo.arn}: $IMAGE_TAG
      - cd../../
      - echo $PWD
      - printf  '{"MultiModalAppImageURI":"%s"}' ${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com/${aws_ecr_repository.multi_modal_app_image_repo.arn}: $IMAGE_TAG > imageDetail.json
artifacts :
  files:
  - imageDetail.json
EOF
  }
  environment {
    type         = "LINUX_CONTAINER"
    image        = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
    compute_type = "BUILD_GENERAL1_SMALL"
  }
  service_role  = aws_iam_role.multi_modal_app_code_build_execution_role.arn
  build_timeout = 10
}

resource "aws_iam_role" "invalidate_cache_function_role" {
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
              "codepipeline:PutJobFailureResult",
              "codepipeline:PutJobSuccessResult",
              "cloudfront:CreateInvalidation"
            ]
            Resource = [
              "*"
            ]
          },
          {
            Effect = "Allow"
            Action = [
              "s3:GetObject",
              "s3:GetObjectAcl",
              "s3:ListBucket"
            ]
            Resource = [
              "arn:aws:s3:::${aws_s3_bucket.multi_modal_artifact_store.id}/*"
            ]
          }
        ]
      }
    }
  ]
}

resource "aws_lambda_function" "invalidate_cache_function" {
  handler  = "index.handler"
  role     = aws_iam_role.invalidate_cache_function_role.arn
  timeout  = 300
  runtime  = "python3.12"
  source_code_hash = filebase64sha256("invalidate_cache.zip")
  filename = "${path.module}/lambdas/invalidate_cache.zip"

  environment {
    variables = {
      ENVIRONMENT_NAME = var.environment_name
    }
  }

}

resource "aws_datapipeline_pipeline" "multi_modal_code_pipe_line_infra" {
  name = join("-", [
    "MultiModalCodePipeLine", var.environment_name
  ])
  // CF Property(ArtifactStore) = {
  //   Location = aws_s3_bucket.multi_modal_artifact_store.id
  //   Type = "S3"
  // }
  // CF Property(RestartExecutionOnUpdate) = false
  // CF Property(RoleArn) = aws_iam_role.multi_modal_code_pipeline_service_role.arn
  tags = [
    {
      Name = "Source"
      Actions = [
        {
          Name = "SourceAction"
          ActionTypeId = {
            Category = "Source"
            Owner    = "AWS"
            Provider = "S3"
            Version  = 1
          }
          Configuration = {
            S3Bucket             = aws_s3_bucket.multi_modal_code_s3_bucket.id
            S3ObjectKey          = "app.zip"
            PollForSourceChanges = false
          }
          RunOrder = 1
          OutputArtifacts = [
            {
              Name = "source-output-artifacts"
            }
          ]
        }
      ]
    },
    {
      Name = "BuildApp"
      Actions = [
        {
          Name = "BuildApp"
          ActionTypeId = {
            Category = "Build"
            Owner    = "AWS"
            Version  = 1
            Provider = "CodeBuild"
          }
          OutputArtifacts = [
            {
              Name = "build-app-output-artifacts"
            }
          ]
          InputArtifacts = [
            {
              Name = "source-output-artifacts"
            }
          ]
          Configuration = {
            ProjectName = aws_codebuild_project.multi_modal_app_code_build.arn
          }
          RunOrder = 1
        },
        {
          Name = "BuildIngestion"
          ActionTypeId = {
            Category = "Build"
            Owner    = "AWS"
            Version  = 1
            Provider = "CodeBuild"
          }
          OutputArtifacts = [
            {
              Name = "build-ingest-output-artifacts"
            }
          ]
          InputArtifacts = [
            {
              Name = "source-output-artifacts"
            }
          ]
          Configuration = {
            ProjectName = aws_codebuild_project.multi_modal_step_function_code_build.arn
          }
          RunOrder = 1
        }
      ]
    },
    {
      Name = "AppInfrastructureDeploy"
      Actions = [
        {
          Name = "DeployApp"
          ActionTypeId = {
            Category = "Deploy"
            Owner    = "AWS"
            Version  = 1
            Provider = "CloudFormation"
          }
          InputArtifacts = [
            {
              Name = "source-output-artifacts"
            },
            {
              Name = "build-app-output-artifacts"
            }
          ]
          OutputArtifacts = [
            {
              Name = "cfn-app-output-artifacts"
            }
          ]
          Configuration = {
            OutputFileName     = "CreateStackOutput.json"
            ActionMode         = "CREATE_UPDATE"
            Capabilities       = "CAPABILITY_NAMED_IAM"
            ParameterOverrides = "{"MultiModalAppImageURI" : { "Fn : :
            GetParam" : ["build-app-output-artifacts", "imageDetail.json", "MultiModalAppImageURI"] },
            "S3DataBucketName" : "${aws_s3_bucket.s3_data_bucket_name.id}", "MultiModalCluster" : "${// Unable to resolve Fn::GetAtt with value: [
//   "Infrastructure",
//   "Outputs.MultiModalCluster"
// ] because 'Fn::GetAtt - Resource "Infrastructure" not found in template.'}",
            "MultiModalCodeS3Bucket" : "${aws_s3_bucket.multi_modal_code_s3_bucket.id}",
            "ContainerPort" : "${var.container_port}", "Cpu" : "${var.cpu}", "Memory" : "${var.memory}",
            "Task" : "${var.desired_task_count}", "Min" : "${var.min_containers}", "Max" : "${var.max_containers}",
            "Tv" : "${var.auto_scaling_target_value}",
            "StreamlitLogsPolicyArn" : "${// Unable to resolve Fn::GetAtt with value: [
//   "Infrastructure",
//   "Outputs.LogsPolicy"
// ] because 'Fn::GetAtt - Resource "Infrastructure" not found in template.'}", "StreamlitPublicSubnetA" : "${// Unable to resolve Fn::GetAtt with value: [
//   "Infrastructure",
//   "Outputs.PublicSubnetA"
// ] because 'Fn::GetAtt - Resource "Infrastructure" not found in template.'}", "StreamlitPublicSubnetB" : "${// Unable to resolve Fn::GetAtt with value: [
//   "Infrastructure",
//   "Outputs.PublicSubnetB"
// ] because 'Fn::GetAtt - Resource "Infrastructure" not found in template.'}",
            "StreamlitPrivateSubnetA" : "${// Unable to resolve Fn::GetAtt with value: [
//   "Infrastructure",
//   "Outputs.PrivateSubnetA"
// ] because 'Fn::GetAtt - Resource "Infrastructure" not found in template.'}", "StreamlitPrivateSubnetB" : "${// Unable to resolve Fn::GetAtt with value: [
//   "Infrastructure",
//   "Outputs.PrivateSubnetB"
// ] because 'Fn::GetAtt - Resource "Infrastructure" not found in template.'}", "LoggingBucketName" : "${// Unable to resolve Fn::GetAtt with value: [
//   "Infrastructure",
//   "Outputs.LoggingBucket"
// ] because 'Fn::GetAtt - Resource "Infrastructure" not found in template.'}",
            "MultiModalVPC" : "${// Unable to resolve Fn::GetAtt with value: [
//   "Infrastructure",
//   "Outputs.VPC"
// ] because 'Fn::GetAtt - Resource "Infrastructure" not found in template.'}",
            "EnvironmentName" : "${var.environment_name}", "CognitoUserPoolId" : "${var.cognito_user_pool_id}",
            "CognitoAppClientId" : "${var.cognito_app_client_id}"
          }
          "
          RoleArn      = aws_iam_role.multi_modal_cloudformation_execution_role.arn
          StackName    = "${local.stack_name}-deploy-${var.environment_name}"
          TemplatePath = "source-output-artifacts::cloudformation/deploy.yaml"
        }
        RunOrder = 1
        },
        {
        Name = "DeployIngest"
        ActionTypeId = {
        Category = "Deploy"
        Owner = "AWS"
        Version = 1
        Provider = "CloudFormation"
        }
        InputArtifacts = [
        {
        Name = "source-output-artifacts"
        },
        {
        Name = "build-ingest-output-artifacts"
        }
        ]
        OutputArtifacts = [
        {
        Name = "cfn-ingest-output-artifacts"
        }
        ]
        Configuration = {
        OutputFileName = "CreateIngestStackOutput.json"
        ActionMode = "CREATE_UPDATE"
        Capabilities = "CAPABILITY_NAMED_IAM,CAPABILITY_AUTO_EXPAND"
        ParameterOverrides = "{
        "EnvironmentName" : "${var.environment_name}",
        "S3DataBucketName" : "${aws_s3_bucket.s3_data_bucket_name.id}",
        "S3DataPrefixKB" : "${var.s3_data_prefix_kb}",
        "VPC" : "${// Unable to resolve Fn::GetAtt with value: [
//   "Infrastructure",
//   "Outputs.VPC"
// ] because 'Fn::GetAtt - Resource "Infrastructure" not found in template.'}",
        "PrivateSubnetA" : "${// Unable to resolve Fn::GetAtt with value: [
//   "Infrastructure",
//   "Outputs.PrivateSubnetA"
// ] because 'Fn::GetAtt - Resource "Infrastructure" not found in template.'}",
        "PrivateSubnetB" : "${// Unable to resolve Fn::GetAtt with value: [
//   "Infrastructure",
//   "Outputs.PrivateSubnetB"
// ] because 'Fn::GetAtt - Resource "Infrastructure" not found in template.'}"
        }
        "
        RoleArn = aws_iam_role.multi_modal_cloudformation_execution_role.arn
        StackName = "${local.stack_name}-data-ingestion-deploy-${var.environment_name}"
        TemplatePath = "build-ingest-output-artifacts::src/sam_deploy/packaged.yaml"
        }
        RunOrder = 1
        }
      ]
    },
    {
      Name = "InvalidateCache"
      Actions = [
        {
          Name = "Invalidate"
          ActionTypeId = {
            Category = "Invoke"
            Owner    = "AWS"
            Version  = 1
            Provider = "Lambda"
          }
          InputArtifacts = [
            {
              Name = "cfn-app-output-artifacts"
            }
          ]
          Configuration = {
            FunctionName = aws_lambda_function.invalidate_cache_function.arn
          }
          RunOrder = 1
        }
      ]
    }
  ]
}
