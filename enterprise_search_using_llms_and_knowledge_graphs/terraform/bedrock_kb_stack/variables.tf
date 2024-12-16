variable knowledge_base_name {
  description = "The name of the knowledge base."
  type = string
  default = "multimodal-enterprise-search-kb"
}

variable knowledge_base_description {
  description = "The description of the knowledge base."
  type = string
  default = "This is a knowledge base for storing multimodal enterprise search documents."
}

variable data_source_name {
  description = "The name of the data source."
  type = string
  default = "multimodal-enterprise-search-data-source"
}

variable data_source_description {
  description = "The description of the data source."
  type = string
  default = "This is a sample data source."
}

variable amazon_bedrock_execution_role_for_kb_arn {
  description = "The ARN of the AmazonBedrockExecutionRoleForKnowledgeBase."
  type = string
}

variable collection_arn {
  description = "The ARN of the collection."
  type = string
}

variable s3_bucket_arn {
  description = "The ARN of the S3 bucket."
  type = string
}

variable s3_data_prefix_kb {
  description = "The S3 prefix of the knowledge base source data"
  type = string
}

variable environment_name {
  description = "Unique name to distinguish different web application in the same AWS account (min length 1 and max length 4)"
  type = string
}