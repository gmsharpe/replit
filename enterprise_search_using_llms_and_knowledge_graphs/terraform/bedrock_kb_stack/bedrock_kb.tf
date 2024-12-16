// Existing Terraform src code found at /tmp/terraform_src.

data "aws_region" "current" {}

data "aws_partition" "current" {}

resource "aws_bedrockagent_knowledge_base" "knowledge_base_with_aoss" {
  name = "${var.knowledge_base_name}-${var.environment_name}"
  description = var.knowledge_base_description
  role_arn = var.amazon_bedrock_execution_role_for_kb_arn
  knowledge_base_configuration {
    type = "VECTOR"
    vector_knowledge_base_configuration {
      embedding_model_arn = "arn:${data.aws_partition.current.partition}:bedrock:${data.aws_region.current.name}::foundation-model/amazon.titan-embed-text-v2:0"
    }
  }
  storage_configuration {
    type = "OPENSEARCH_SERVERLESS"
    opensearch_serverless_configuration {
      collection_arn = var.collection_arn
      vector_index_name = "bedrock-multimodal-index"
      field_mapping = {
        VectorField = "vector"
        TextField = "text"
        MetadataField = "metadata"
      }
    }
  }
}

resource "aws_bedrockagent_data_source" "sample_data_source" {
  knowledge_base_id = aws_bedrockagent_knowledge_base.knowledge_base_with_aoss.arn
  data_deletion_policy = "RETAIN"
  name = "${var.data_source_name}-${var.environment_name}"
  description = var.data_source_description
  data_source_configuration {
    type = "S3"
    s3_configuration = {
      BucketArn = var.s3_bucket_arn
      InclusionPrefixes = [
        "${var.s3_data_prefix_kb}/"
      ]
    }
  }
}

resource "aws_ssm_parameter" "knowledge_base_id" {
  name = "/multimodalapp/${var.environment_name}/KnowledgeBaseId"
  type = "String"
  value = aws_bedrockagent_knowledge_base.knowledge_base_with_aoss.id
  description = "SSM Parameter for knowledge base Id"
  allowed_pattern = ".*"
}

resource "aws_ssm_parameter" "data_source_id" {
  name = "/multimodalapp/${var.environment_name}/DataSourceId"
  type = "String"
  value = aws_bedrockagent_data_source.sample_data_source.data_source_id
  description = "SSM Parameter for Data Source Id"
  allowed_pattern = ".*"
}
