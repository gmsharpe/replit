variable aoss_collection_name {
  description = "Name of the Amazon OpenSearch Service Serverless (AOSS) collection."
  type = string
}

variable s3_data_bucket_name {
  description = "Name of the S3 bucket to sync."
  type = string
}

variable s3_data_prefix_kb {
  description = "Name of the S3 prefix to sync"
  type = string
}

variable environment_name {
  description = "Unique name to distinguish different web application in the same AWS account (min length 1 and max length 4)"
  type = string
}
