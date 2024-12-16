// Existing Terraform src code found at /tmp/terraform_src.

data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

resource "aws_opensearchserverless_access_policy" "data_access_policy" {
  name = "multimodal-apolicy-${var.environment_name}"
  type = "data"
  description = "Access policy for vectordb collection"
  policy = "[{"Description":"Access for cfn user","Rules":[{"ResourceType":"index","Resource":["index/*/*"],"Permission":["aoss:*"]}, {"ResourceType":"collection","Resource":["collection/vectordb"],"Permission":["aoss:*"]}], "Principal":["${aws_iam_role.amazon_bedrock_execution_role_for_kb.arn}","${aws_iam_role.lambda_aoss_index_creation_execution_role.arn}"]}]"
}

resource "aws_opensearchserverless_security_policy" "network_policy" {
  name = "multimodal-npolicy-${var.environment_name}"
  type = "network"
  description = "Network policy for vectordb collection"
  policy = "[{"Rules":[{"ResourceType":"collection","Resource":["collection/${var.aoss_collection_name_prefix}-${var.environment_name}"]}, {"ResourceType":"dashboard","Resource":["collection/${var.aoss_collection_name_prefix}-${var.environment_name}"]}],"AllowFromPublic":true}]"
}

resource "aws_opensearchserverless_security_policy" "encryption_policy" {
  name = "multimodal-epolicy-${var.environment_name}"
  type = "encryption"
  description = "Encryption policy for vectordb collection"
  policy = "{"Rules":[{"ResourceType":"collection","Resource":["collection/${var.aoss_collection_name_prefix}-${var.environment_name}"]}],"AWSOwnedKey":true}"
}

resource "aws_opensearchserverless_collection" "collection" {
  name = "${var.aoss_collection_name_prefix}-${var.environment_name}"
  type = "VECTORSEARCH"
  description = "Collection to holds Vector Embeddings and Text"
}

resource "aws_iam_role" "amazon_bedrock_execution_role_for_kb" {
  name = join("-", ["AmazonBedrockExecutionRoleForKB", var.aoss_collection_name_prefix, var.environment_name])
  assume_role_policy = {
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "bedrock.amazonaws.com"
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            aws:SourceAccount = "${data.aws_caller_identity.current.account_id}"
          }
          ArnLike = {
            AWS:SourceArn = "arn:aws:bedrock:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:knowledge-base/*"
          }
        }
      }
    ]
  }
  force_detach_policies = [
    {
      PolicyName = "S3ReadOnlyAccess"
      PolicyDocument = {
        Version = "2012-10-17"
        Statement = [
          {
            Effect = "Allow"
            Action = [
              "s3:Get*",
              "s3:List*"
            ]
            Resource = "*"
          }
        ]
      }
    },
    {
      PolicyName = "AOSSAPIAccessAll"
      PolicyDocument = {
        Version = "2012-10-17"
        Statement = [
          {
            Effect = "Allow"
            Action = [
              "aoss:APIAccessAll"
            ]
            Resource = "arn:aws:aoss:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:collection/*"
          }
        ]
      }
    },
    {
      PolicyName = "BedrockListAndInvokeModel"
      PolicyDocument = {
        Version = "2012-10-17"
        Statement = [
          {
            Effect = "Allow"
            Action = [
              "bedrock:ListCustomModels"
            ]
            Resource = "*"
          },
          {
            Effect = "Allow"
            Action = [
              "bedrock:InvokeModel"
            ]
            Resource = "arn:aws:bedrock:${data.aws_region.current.name}::foundation-model/*"
          }
        ]
      }
    }
  ]
}

resource "aws_iam_role" "lambda_aoss_index_creation_execution_role" {
  name = join("-", ["LambdaAOSSIndexCreationExecutionRole", var.aoss_collection_name_prefix, var.environment_name])
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
              "s3:Put*",
              "s3:List*"
            ]
            Resource = "*"
          }
        ]
      }
    },
    {
      PolicyName = "AOSSAPIAccessAll"
      PolicyDocument = {
        Version = "2012-10-17"
        Statement = [
          {
            Effect = "Allow"
            Action = [
              "aoss:APIAccessAll"
            ]
            Resource = "arn:aws:aoss:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:collection/*"
          }
        ]
      }
    },
    {
      PolicyName = "BedrockListAndInvokeModel"
      PolicyDocument = {
        Version = "2012-10-17"
        Statement = [
          {
            Effect = "Allow"
            Action = [
              "bedrock:ListCustomModels"
            ]
            Resource = "*"
          },
          {
            Effect = "Allow"
            Action = [
              "bedrock:InvokeModel"
            ]
            Resource = "arn:aws:bedrock:${data.aws_region.current.name}::foundation-model/*"
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

resource "aws_ssm_parameter" "collection_endpoint" {
  name = "/multimodalapp/${var.environment_name}/CollectionEndpointURL"
  type = "String"
  value = aws_opensearchserverless_collection.collection.collection_endpoint
  description = "SSM Parameter for Collection Endpoint URL"
  allowed_pattern = ".*"
}

resource "aws_lambda_function" "lambda_aoss_index_creation" {
  handler = "index.handler"
  function_name = "lambdaaossindexcreation-${var.environment_name}"
  reserved_concurrent_executions = 5
  role = aws_iam_role.lambda_aoss_index_creation_execution_role.arn
  runtime = "python3.12"
  layers = [
    "arn:aws:lambda:${data.aws_region.current.name}:336392948345:layer:AWSSDKPandas-Python312:8"
  ]
  code_signing_config_arn = {
    ZipFile = "# Create the vector index in Opensearch serverless, with the knn_vector field index mapping, specifying the dimension size, name and engine.
import boto3
import json
from opensearchpy import OpenSearch, RequestsHttpConnection, AWSV4SignerAuth, RequestError
from urllib.parse import urlparse
import cfnresponse
import time


def handler(event,context):
    try:

        sts_client = boto3.client('sts')
        boto3_session = boto3.session.Session()
        region = boto3_session.region_name

        if event['RequestType'] == 'Delete':
            cfnresponse.send(event, context, cfnresponse.SUCCESS, {})
            return
        if event['RequestType'] == 'Update':
            cfnresponse.send(event, context, cfnresponse.SUCCESS, {})
            return

        if event['RequestType'] == 'Create':

            service = "aoss"
            region_name = region

            credentials = boto3.Session().get_credentials()
            awsauth = AWSV4SignerAuth(credentials, region_name, service)

            ssm_client = boto3.client('ssm')

            body_json = {
              "settings": {
                  "index.knn": "true",
                  "number_of_shards": 1,
                  "knn.algo_param.ef_search": 512,
                  "number_of_replicas": 0,
              },
              "mappings": {
                  "properties": {
                    "vector": {
                        "type": "knn_vector",
                        "dimension": 1024,
                        "method": {
                            "name": "hnsw",
                            "engine": "faiss",
                            "space_type": "l2"
                        },
                    },
                    "text": {
                        "type": "text"
                    },
                    "metadata": {
                        "type": "text"         }
                  }
              }
            }


            response = ssm_client.get_parameter(Name='/multimodalapp/${var.environment_name}/CollectionEndpointURL')

            paramval =  response['Parameter']['Value']

            index_name = f"bedrock-multimodal-index"
            host = urlparse(paramval).netloc

            oss_client = OpenSearch(
            hosts=[{'host': host, 'port': 443}],
            http_auth=awsauth,
            use_ssl=True,
            verify_certs=True,
            connection_class=RequestsHttpConnection,
            timeout=300
            )


            response = oss_client.indices.create(index=index_name, body=json.dumps(body_json))
            print('\nCreating index:')

            responseData = {'acknowledged': response['acknowledged']}
            cfnresponse.send(event, context, cfnresponse.SUCCESS, responseData)
            return
    except Exception as e:
            cfnresponse.send(event, context, cfnresponse.FAILED, {'Message': str(e)})
"
  }
  timeout = 900
  memory_size = 10240
}

resource "aws_customerprofiles_domain" "build_oss_index" {
  // CF Property(ServiceToken) = aws_lambda_function.lambda_aoss_index_creation.arn
}

output "dashboard_url" {
  value = aws_opensearchserverless_collection.collection.dashboard_endpoint
}

output "collection_arn" {
  value = aws_opensearchserverless_collection.collection.arn
}

output "collection_endpoint" {
  value = aws_opensearchserverless_collection.collection.collection_endpoint
}

output "amazon_bedrock_execution_role_for_kb_arn" {
  value = aws_iam_role.amazon_bedrock_execution_role_for_kb.arn
}

output "lambda_aoss_index_creation_execution_role_arn" {
  value = aws_iam_role.lambda_aoss_index_creation_execution_role.arn
}

output "aoss_collection_name" {
  value = "${var.aoss_collection_name_prefix}-${var.environment_name}"
}
