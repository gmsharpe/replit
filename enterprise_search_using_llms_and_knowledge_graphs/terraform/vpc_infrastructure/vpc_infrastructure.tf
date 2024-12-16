// Existing Terraform src code found at /tmp/terraform_src.

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  mappings = {
    ELBRegionMap = {
      us-east-1 = {
        ELBAccountId = "127311923021"
      }
      us-west-2 = {
        ELBAccountId = "797873946194"
      }
    }
  }
  stack_name = "vpc_infrastructure"
}


resource "aws_ecs_cluster" "multi_modal_cluster" {
  name = join("-", ["MultiModalCluster", var.environment_name])
  setting = [
    {
      Name  = "containerInsights"
      Value = "enabled"
    }
  ]
}

resource "aws_iam_policy" "logs_policy" {
  path = "/"
  name = "LogsPolicy${var.environment_name}"
  policy = {
    Version = "2012-10-17"
    Statement = [
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

resource "aws_s3_bucket" "logging_bucket" {
  // CF Property(OwnershipControls) = {
  //   Rules = [
  //     {
  //       ObjectOwnership = "BucketOwnerPreferred"
  //     }
  //   ]
  // }
  // CF Property(PublicAccessBlockConfiguration) = {
  //   BlockPublicAcls = true
  //   BlockPublicPolicy = true
  //   IgnorePublicAcls = true
  //   RestrictPublicBuckets = true
  // }
  versioning {
    // CF Property(Status) = "Enabled"
  }
}

resource "aws_s3_bucket_policy" "logging_bucket_policy" {
  bucket = aws_s3_bucket.logging_bucket.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:PutObject"
        ]
        Effect = "Allow"
        Principal = {
          Service = "logging.s3.amazonaws.com"
        }
        Resource = [
          "arn:aws:s3:::${aws_s3_bucket.logging_bucket.id}/*"
        ]
      },
      {
        Action = [
          "s3:PutObject"
        ]
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${local.mappings["ELBRegionMap"][data.aws_region.current.name]["ELBAccountId"]}:root"
        }
        Resource = [
          "arn:aws:s3:::${aws_s3_bucket.logging_bucket.id}/alb/logs/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        ]
      },
      {
        Action = [
          "s3:*"
        ]
        Effect = "Deny"
        Resource = [
          "arn:aws:s3:::${aws_s3_bucket.logging_bucket.id}/*",
          "arn:aws:s3:::${aws_s3_bucket.logging_bucket.id}"
        ]
        Principal = "*"
        Condition = {
          Bool = {
            aws : SecureTransport = "false"
          }
        }
      }
    ]
  }
  )
}

resource "aws_vpc" "vpc" {
  cidr_block           = var.vpccidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "VPC"
  }
}

resource "aws_cloudwatch_log_group" "vpc_log_group" {
  retention_in_days = 7
}

resource "aws_iam_role" "vpc_log_role" {
  assume_role_policy = {
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  }
  managed_policy_arns = [
    aws_iam_policy.logs_policy.policy
  ]
}

resource "aws_flow_log" "vpc_flow_log" {
  eni_id               = aws_vpc.vpc.arn
  log_destination_type = "VPC"
  traffic_type         = "ALL"
  log_group_name       = aws_cloudwatch_log_group.vpc_log_group.arn
  iam_role_arn         = aws_iam_role.vpc_log_role.arn
}

resource "aws_internet_gateway" "internet_gateway" {
  tags = {
    Name = "InternetGateway"
  }
}

resource "aws_vpn_gateway_attachment" "internet_gateway_attachment" {
  vpc_id = aws_vpc.vpc.arn
}

resource "aws_subnet" "public_subnet_a" {
  cidr_block = var.public_subnet_acidr
  vpc_id     = aws_vpc.vpc.arn
  availability_zone = element()
  // Unable to resolve Fn::GetAZs with value: data.aws_region.current.name because local variable 'az_data' referenced before assignment, 0)
  tags {
    Name = "PublicSubnetA"
  }
}

resource "aws_subnet" "public_subnet_b" {
  cidr_block = var.public_subnet_bcidr
  vpc_id     = aws_vpc.vpc.arn
  availability_zone = element()
  // Unable to resolve Fn::GetAZs with value: data.aws_region.current.name because local variable 'az_data' referenced before assignment, 1)
  tags = {
    Name = "PublicSubnetB"
  }
}

resource "aws_subnet" "private_subnet_a" {
  cidr_block = var.private_subnet_acidr
  vpc_id     = aws_vpc.vpc.arn
  availability_zone = element()
  // Unable to resolve Fn::GetAZs with value: data.aws_region.current.name because local variable 'az_data' referenced before assignment, 0)
  tags = {
    Name = "PrivateSubnetA"
  }
}

resource "aws_subnet" "private_subnet_b" {
  cidr_block = var.private_subnet_bcidr
  vpc_id     = aws_vpc.vpc.arn
  availability_zone = element()
  // Unable to resolve Fn::GetAZs with value: data.aws_region.current.name because local variable 'az_data' referenced before assignment, 1)
  tags = {
    Name = "PrivateSubnetB"
  }
}

resource "aws_ec2_fleet" "nat_gateway_aeip" {
  // CF Property(Domain) = "vpc"
}

resource "aws_ec2_fleet" "nat_gateway_beip" {
  // CF Property(Domain) = "vpc"
}

resource "aws_nat_gateway" "nat_gateway_a" {
  allocation_id = aws_ec2_fleet.nat_gateway_aeip.id
  subnet_id     = aws_subnet.public_subnet_a.id
}

resource "aws_nat_gateway" "nat_gateway_b" {
  allocation_id = aws_ec2_fleet.nat_gateway_beip.id
  subnet_id     = aws_subnet.public_subnet_b.id
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.vpc.arn
  tags = {
    Name = "PublicRouteTable"
  }
}

resource "aws_route" "default_public_route" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.internet_gateway.id
}

resource "aws_route_table_association" "public_subnet_a_route_table_association" {
  route_table_id = aws_route_table.public_route_table.id
  subnet_id      = aws_subnet.public_subnet_a.id
}

resource "aws_route_table_association" "public_subnet_b_route_table_association" {
  route_table_id = aws_route_table.public_route_table.id
  subnet_id      = aws_subnet.public_subnet_b.id
}

resource "aws_route_table" "private_route_table_a" {
  vpc_id = aws_vpc.vpc.arn
  tags = {
    Name = "PrivateRouteTableA"
  }
}

resource "aws_route" "default_private_route_a" {
  route_table_id         = aws_route_table.private_route_table_a.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gateway_a.association_id
}

resource "aws_route_table_association" "private_subnet_a_route_table_association" {
  route_table_id = aws_route_table.private_route_table_a.id
  subnet_id      = aws_subnet.private_subnet_a.id
}

resource "aws_route_table" "private_route_table_b" {
  vpc_id = aws_vpc.vpc.arn
  tags = {
    Name = "PrivateRouteTableB"
  }
}

resource "aws_route" "default_private_route_b" {
  route_table_id         = aws_route_table.private_route_table_b.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gateway_b.association_id
}

resource "aws_route_table_association" "private_subnet_b_route_table_association" {
  route_table_id = aws_route_table.private_route_table_b.id
  subnet_id      = aws_subnet.private_subnet_b.id
}

resource "aws_security_group" "vpc_endpoint_security_group" {
  vpc_id      = aws_vpc.vpc.arn
  name        = "VPC Endpoint Security Group"
  description = "Group allowing traffic"
  ingress = [
    {
      protocol    = "tcp"
      from_port   = "443"
      to_port     = "443"
      cidr_blocks = "0.0.0.0/0"
    }
  ]
  egress = [
    {
      description = "Allow all outbound traffic"
      protocol    = "-1"
      cidr_blocks = "0.0.0.0/0"
    }
  ]
  tags = {
    Name = "VPC Endpoint Security Group"
  }
}

resource "aws_iam_role" "multi_modal_ecs_role_custom_resource_role" {
  name = join("-", ["ECSRole", "${local.stack_name}"])
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
    aws_iam_policy.logs_policy.policy
  ]
  force_detach_policies = [
    {
      PolicyName = "IAMPolicy"
      PolicyDocument = {
        Version = "2012-10-17"
        Statement = [
          {
            Effect = "Allow"
            Action = [
              "iam:ListRoles"
            ]
            Resource = [
              "*"
            ]
          },
          {
            Effect = "Allow"
            Action = [
              "iam:GetRole",
              "iam:CreateServiceLinkedRole",
              "iam:AttachRolePolicy"
            ]
            Resource = [
              "*"
            ]
          },
          {
            Effect = "Allow"
            Action = [
              "ec2:DescribeNetworkInterfaces",
              "ec2:DeleteNetworkInterface",
              "ec2:DescribeInstances",
              "ec2:DetachNetworkInterface"
            ]
            Resource = [
              "*"
            ]
          }
        ]
      }
    }
  ]
}

resource "aws_lambda_function" "multi_modal_ecs_role_custom_resource_function" {
  function_name = join("-", ["ECSCF", local.stack_name])
  handler = "index.handler"
  role    = aws_iam_role.multi_modal_ecs_role_custom_resource_role.arn
  timeout = 300
  runtime = "python3.12"
  source_code_hash = filebase64sha256("ecs_role_resource_lambda.zip")

  filename = "${path.module}/ecs_role_resource_lambda.zip"

  environment {
    variables = {
      ENVIRONMENT_NAME = var.environment_name
    }
  }

}

data "archive_file" "multi_modal_ecs_role_custom_resource_function_zip" {
  type        = "zip"
  source_file = "ecs_role_resource_lambda.py"
  output_path = "ecs_role_resource_lambda.zip"
}


resource "aws_kms_custom_key_store" "multi_modal_ecs_role_custom_resource" {
  // CF Property(ServiceToken) = aws_lambda_function.multi_modal_ecs_role_custom_resource_function.arn
  cloud_hsm_cluster_id = aws_vpc.vpc.arn
}

output "vpc" {
  description = "VPC"
  value       = aws_vpc.vpc.arn
}

output "logs_policy" {
  description = "LogsPolicy"
  value       = aws_iam_policy.logs_policy.policy
}

output "logging_bucket" {
  description = "LoggingBucket"
  value       = aws_s3_bucket.logging_bucket.id
}

output "logging_bucket_policy" {
  description = "LoggingBucketPolicy"
  value       = aws_s3_bucket_policy.logging_bucket_policy.bucket
}

output "public_subnet_a" {
  description = "PublicSubnetA"
  value       = aws_subnet.public_subnet_a.id
}

output "public_subnet_b" {
  description = "PublicSubnetB"
  value       = aws_subnet.public_subnet_b.id
}

output "private_subnet_a" {
  description = "PrivateSubnetA"
  value       = aws_subnet.private_subnet_a.id
}

output "private_subnet_b" {
  description = "PrivateSubnetB"
  value       = aws_subnet.private_subnet_b.id
}

output "multi_modal_cluster" {
  description = "MultiModalCluster"
  value       = aws_ecs_cluster.multi_modal_cluster.arn
}
