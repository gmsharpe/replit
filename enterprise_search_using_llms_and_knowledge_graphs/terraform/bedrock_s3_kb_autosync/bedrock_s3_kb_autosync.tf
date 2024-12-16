// Existing Terraform src code found at /tmp/terraform_src.

resource "aws_iam_role" "lambda_kb_sync_execution_role" {
  name = join("-", ["LambdaKBSyncExecutionRole", var.aoss_collection_name, var.environment_name])
  assume_role_policy = {
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  }
  force_detach_policies = [
    {
      PolicyName = "S3Access"
      PolicyDocument = {
        Version = "2012-10-17"
        Statement = [
          {
            Effect = "Allow"
            Action = [
              "logs:CreateLogGroup",
              "logs:CreateLogStream",
              "logs:PutLogEvents"
            ]
            Resource = "arn:aws:logs:*:*:*"
          },
          {
            Effect = "Allow"
            Action = [
              "s3:Get*",
              "s3:List*",
              "s3:Put*"
            ]
            Resource = "*"
          }
        ]
      }
    },
    {
      PolicyName = "BedrockAPIPolicy"
      PolicyDocument = {
        Version = "2012-10-17"
        Statement = [
          {
            Effect = "Allow"
            Action = [
              "bedrock:Invoke*",
              "bedrock:StartIngestionJob"
            ]
            Resource = "*"
          }
        ]
      }
    },
    {
      PolicyName = "SSMParameterAccess"
      PolicyDocument = {
        Version = "2012-10-17"
        Statement = [
          {
            Effect = "Allow"
            Action = [
              "ssm:GetParameters",
              "ssm:GetParameter",
              "ssm:GetParameterHistory",
              "ssm:GetParametersByPath"
            ]
            Resource = "*"
          }
        ]
      }
    }
  ]
}

resource "aws_lambda_function" "lambda_kb_sync" {
  function_name = "lambdakbsync-${var.environment_name}"
  handler = "index.handler"
  reserved_concurrent_executions = 5
  role = aws_iam_role.lambda_kb_sync_execution_role.arn
  runtime = "python3.12"
  code_signing_config_arn = {
    ZipFile = "import os
    import json
    import boto3

    bedrockClient = boto3.client('bedrock-agent')

    def handler(event, context):
    print('Inside Lambda Handler')
    print('event: ', event)

    ssm_client = boto3.client('ssm')

    responseKnowledgeBaseId = ssm_client.get_parameter(
    Name='/multimodalapp/${var.environment_name}/KnowledgeBaseId')
    responseDataSourceId = ssm_client.get_parameter(
    Name='/multimodalapp/${var.environment_name}/DataSourceId')

    KnowledgeBaseId=responseKnowledgeBaseId['Parameter']['Value']
    DataSourceId=responseDataSourceId['Parameter']['Value']
    response = bedrockClient.start_ingestion_job(
    knowledgeBaseId=KnowledgeBaseId,
    dataSourceId=DataSourceId
    )

    print('Ingestion Job Response: ', response)

    return {
    'statusCode': 200,
    'body': json.dumps('response')
    }
    "
  }
  timeout = 900
  memory_size = 10240
}

resource "aws_cloudwatch_event_rule" "brkb_ingestion_rules" {
  description = "This event rule triggers the bedrock ingestion Lambda function"
  event_pattern = {
    source = [
      "aws.s3"
    ]
    detail-type = [
      "Object Created",
      "Object Deleted"
    ]
    detail = {
      bucket = {
        name = [
          var.s3_data_bucket_name
        ]
      }
      object = {
        key = [
          {
            prefix = var.s3_data_prefix_kb
          }
        ]
      }
    }
  }
  state = "ENABLED"
  // CF Property(Targets) = [
  //   {
  //     Arn = aws_lambda_function.lambda_kb_sync.arn
  //     Id = "brkb-ingestion-event-rule"
  //     RetryPolicy = {
  //       MaximumEventAgeInSeconds = 43201
  //     }
  //   }
  // ]
}

resource "aws_lambda_permission" "lambda_invoke_permission" {
  function_name = aws_lambda_function.lambda_kb_sync.arn
  action = "lambda:InvokeFunction"
  principal = "events.amazonaws.com"
  source_arn = aws_cloudwatch_event_rule.brkb_ingestion_rules.arn
}
