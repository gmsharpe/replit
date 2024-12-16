
variable environment_name {
  description = "Unique name to distinguish different web application in the same AWS account (min length 1 and max length 4)"
  type = string
}

variable aoss_collection_name_prefix {
  description = "Name of the Amazon OpenSearch Service Serverless (AOSS) collection."
  type = string
  default = "multimodal-search"
}
