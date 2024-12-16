// Existing Terraform src code found at /tmp/terraform_src.

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}


resource "aws_s3_bucket" "multi_modal_artifact_store" {
  logging {
    // Unable to resolve Fn::GetAtt with value: [
    //   "Infrastructure",
    //   "Outputs.LoggingBucket"
    // ] because 'Fn::GetAtt - Resource "Infrastructure" not found in template.'
    // CF Property(LogFilePrefix) = "artifact-${var.environment_name}-logs"
  }
}

resource "aws_s3_bucket" "s3_data_bucket_name" {
  versioning {
    // CF Property(Status) = "Enabled"
  }
  // CF Property(PublicAccessBlockConfiguration) = {
  //   BlockPublicAcls = true
  //   BlockPublicPolicy = true
  //   IgnorePublicAcls = true
  //   RestrictPublicBuckets = true
  // }
  replication_configuration {
    // CF Property(EventBridgeConfiguration) = {
    //   EventBridgeEnabled = true
    // }
  }
}

resource "aws_s3_bucket_policy" "s3_data_bucket_name_bucket_policy" {
  bucket = aws_s3_bucket.s3_data_bucket_name.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:*"
        ]
        Effect = "Deny"
        Resource = [
          "arn:aws:s3:::${aws_s3_bucket.s3_data_bucket_name.id}/*",
          "arn:aws:s3:::${aws_s3_bucket.s3_data_bucket_name.id}"
        ]
        Principal = "*"
        Condition = {
          Bool = {
            aws:SecureTransport = "false"
          }
        }
      }
    ]
  }
  )
}

resource "aws_s3_bucket" "multi_modal_cloud_trail_bucket" {
  versioning {
    // CF Property(Status) = "Enabled"
  }
  // CF Property(PublicAccessBlockConfiguration) = {
  //   BlockPublicAcls = true
  //   BlockPublicPolicy = true
  //   IgnorePublicAcls = true
  //   RestrictPublicBuckets = true
  // }
}

resource "aws_iam_role" "multi_modal_cloud_watch_event_role" {
  assume_role_policy = {
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = [
            "events.amazonaws.com"
          ]
        }
        Action = "sts:AssumeRole"
      }
    ]
  }
  path = "/"
  force_detach_policies = [
    {
      PolicyName = "cwe-pipeline-execution"
      PolicyDocument = {
        Version = "2012-10-17"
        Statement = [
          {
            Effect = "Allow"
            Action = "codepipeline:StartPipelineExecution"
            Resource = join("", [
              "arn:aws:codepipeline:",
              data.aws_region.current.name,
              ":", data.aws_caller_identity.current.account_id, ":",
              join("-", ["MultiModalCodePipeLine", var.environment_name])
            ])
          }
        ]
      }
    }
  ]
}

resource "aws_cloudwatch_event_rule" "amazon_cloud_watch_event_rule" {
  name = join("-", ["MultiModalEventRule", var.environment_name])
  event_pattern = {
    source = [
      "aws.s3"
    ]
    detail-type = [
      "AWS API Call via CloudTrail"
    ]
    detail = {
      eventSource = [
        "s3.amazonaws.com"
      ]
      eventName = [
        "PutObject",
        "CompleteMultipartUpload"
      ]
      resources = {
        ARN = [
          join("", [aws_s3_bucket.multi_modal_code_s3_bucket.arn, "/", "app.zip"])
        ]
      }
    }
  }
  // CF Property(Targets) = [
  //   {
  //     Arn = join("", ["arn:aws:codepipeline:", data.aws_region.current.name, ":", data.aws_caller_identity.current.account_id, ":", join("-", ["MultiModalCodePipeLine", var.environment_name])])
  //     RoleArn = aws_iam_role.multi_modal_cloud_watch_event_role.arn
  //     Id = "codepipeline-AppPipeline"
  //   }
  // ]
}

resource "aws_s3_bucket_policy" "multi_modal_cloud_trail_bucket_policy" {
  bucket = aws_s3_bucket.multi_modal_cloud_trail_bucket.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = [
            "cloudtrail.amazonaws.com"
          ]
        }
        Action = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.multi_modal_cloud_trail_bucket.arn
      },
      {
        Sid = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = [
            "cloudtrail.amazonaws.com"
          ]
        }
        Action = "s3:PutObject"
        Resource = join("", [aws_s3_bucket.multi_modal_cloud_trail_bucket.arn, "/AWSLogs/", data.aws_caller_identity.current.account_id, "/*"])
        Condition = {
          StringEquals = {
            s3:x-amz-acl = "bucket-owner-full-control"
          }
        }
      },
      {
        Action = [
          "s3:*"
        ]
        Effect = "Deny"
        Resource = [
          "arn:aws:s3:::${aws_s3_bucket.multi_modal_cloud_trail_bucket.id}/*",
          "arn:aws:s3:::${aws_s3_bucket.multi_modal_cloud_trail_bucket.id}"
        ]
        Principal = "*"
        Condition = {
          Bool = {
            aws:SecureTransport = "false"
          }
        }
      }
    ]
  }
  )
}

resource "aws_cloudtrail" "multi_modal_cloud_trail" {
  name = "MultiModalCloudTrail-${var.environment_name}"
  s3_bucket_name = aws_s3_bucket.multi_modal_cloud_trail_bucket.id
  event_selector = [
    {
      data_resource = [
        {
          type = "AWS::S3::Object"
          values = [
            join("", [aws_s3_bucket.multi_modal_code_s3_bucket.arn, "/", "app.zip"])
          ]
        }
      ]
      read_write_type = "WriteOnly"
      include_management_events = false
    }
  ]
  include_global_service_events = true
  is_multi_region_trail = true
}

resource "aws_s3_bucket" "multi_modal_code_s3_bucket" {
  versioning {
    // CF Property(Status) = "Enabled"
  }
  // CF Property(PublicAccessBlockConfiguration) = {
  //   BlockPublicAcls = true
  //   BlockPublicPolicy = true
  //   IgnorePublicAcls = true
  //   RestrictPublicBuckets = true
  // }
}

resource "aws_s3_bucket_policy" "multi_modal_code_s3_bucket_policy" {
  bucket = aws_s3_bucket.multi_modal_code_s3_bucket.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:*"
        ]
        Effect = "Deny"
        Resource = [
          "arn:aws:s3:::${aws_s3_bucket.multi_modal_code_s3_bucket.id}/*",
          "arn:aws:s3:::${aws_s3_bucket.multi_modal_code_s3_bucket.id}"
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