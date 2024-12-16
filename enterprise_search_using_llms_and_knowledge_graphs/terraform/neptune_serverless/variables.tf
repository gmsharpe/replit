
variable private_subnet_a {
  description = "Task private subnet A"
  type = string
}

variable private_subnet_b {
  description = "Task private subnet B"
  type = string
}

variable db_cluster_id {
  description = "A user-specified name for the DB cluster"
  type = string
  default = "multimodalsearch"
}

variable vpc {
  description = "Id of VPC created"
  type = string
}

variable environment_name {
  description = "Unique name to distinguish different web application in the same AWS account (min length 1 and max length 4)"
  type = string
}

variable db_instance_type {
  description = "Neptune DB instance type"
  type = string
  default = "db.serverless"
}

variable min_nc_us {
  description = "Min NCUs to be set on the Neptune cluster(Should be less than or equal to MaxNCUs). Required if DBInstance type is db.serverless"
  type = string
  default = 2
}

variable max_nc_us {
  description = "Max NCUs to be set on the Neptune cluster(Should be greater than or equal to MinNCUs). Required if DBInstance type is db.serverless"
  type = string
  default = 3
}

variable db_replica_identifier_suffix {
  description = "OPTIONAL: The ID for the Neptune Replica to use. Empty means no read replica."
  type = string
}

variable db_cluster_port {
  description = "Enter the port of your Neptune cluster"
  type = string
  default = "8182"
}

variable neptune_query_timeout {
  description = "Neptune Query Time out (in milliseconds)"
  type = string
  default = 20000
}

variable neptune_enable_audit_log {
  description = "Enable Audit Log. 0 means disable and 1 means enable."
  type = string
  default = 0
}

variable iam_auth_enabled {
  description = "Enable IAM Auth for Neptune."
  type = string
  default = "false"
}

variable attach_bulkload_iam_role_to_neptune_cluster {
  description = "Attach Bulkload IAM role to cluster"
  type = string
  default = "true"
}

variable storage_encrypted {
  description = "Enable Encryption for Neptune."
  type = string
  default = "true"
}

variable kms_key_id {
  description = "OPTIONAL: If StorageEncrypted is true, the Amazon KMS key identifier for the encrypted DB cluster."
  type = string
}