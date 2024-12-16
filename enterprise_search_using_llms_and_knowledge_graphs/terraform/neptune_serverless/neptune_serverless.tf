// Existing Terraform src code found at /tmp/terraform_src.

data "aws_region" "current" {}

locals {
  CreateDBReplicaInstance = !var.db_replica_identifier_suffix == ""
  IsDBClusterIdEmptyCondition = var.db_cluster_id == ""
  AZ3NotPresent = anytrue([data.aws_region.current.name == "ca-central-1", data.aws_region.current.name == "us-west-1"])
  AZ3Present = !local.AZ3NotPresent
  AttachBulkloadIAMRoleToNeptuneClusterCondition = var.attach_bulkload_iam_role_to_neptune_cluster == "true"
}


resource "aws_neptune_subnet_group" "neptune_db_subnet_group" {
  description = "Neptune DB subnet group"
  subnet_ids = [
    var.private_subnet_a,
    var.private_subnet_b
  ]
}

resource "aws_security_group" "neptune_sg" {
  vpc_id = var.vpc
  description = "Allow Neptune DBPort Access"
  egress = [
    {
      protocol = "tcp"
      from_port = 443
      to_port = 443
      cidr_blocks = "0.0.0.0/0"
      description = "Allow HTTPS outbound to AWS services"
    }
  ]
  ingress = [
    {
      from_port = var.db_cluster_port
      to_port = var.db_cluster_port
      protocol = "tcp"
      cidr_blocks = "0.0.0.0/0"
      description = "http access"
    }
  ]
  tags = {
    Name = join("-", ["NeptuneDBSecurityGroup", var.environment_name])
  }
}

resource "aws_iam_role" "neptune_load_from_s3_role" {
  assume_role_policy = {
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = [
            "rds.amazonaws.com"
          ]
        }
        Action = [
          "sts:AssumeRole"
        ]
      }
    ]
  }
  path = "/"
}

resource "aws_iam_policy" "neptune_load_from_s3_policy" {
  name = "NeptuneLoadFromS3Policy"
  policy = {
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
  // CF Property(Roles) = [
  //   aws_iam_role.neptune_load_from_s3_role.arn
  // ]
}

resource "aws_neptune_parameter_group" "neptune_db_parameter_group" {
  family = "neptune1.3"
  description = "multimodal neptune-db-parameter-group-description"
  parameter = {
    neptune_query_timeout = var.neptune_query_timeout
  }
}

resource "aws_neptune_cluster_parameter_group" "neptune_db_cluster_parameter_group" {
  family = "neptune1.3"
  description = "multimodal neptune-db-cluster-parameter-group-description"
  parameter = {
    neptune_enable_audit_log = var.neptune_enable_audit_log
  }
}

resource "aws_neptune_cluster" "neptune_db_cluster" {
  engine_version = "1.3.2.1"
  cluster_identifier = local.IsDBClusterIdEmptyCondition ? null : "${var.db_cluster_id}-${var.environment_name}"
  serverless_v2_scaling_configuration = {
    MinCapacity = var.min_nc_us
    MaxCapacity = var.max_nc_us
  }
  neptune_subnet_group_name = aws_neptune_subnet_group.neptune_db_subnet_group.id
  vpc_security_group_ids = [
    aws_security_group.neptune_sg.arn
  ]
  neptune_cluster_parameter_group_name = aws_neptune_cluster_parameter_group.neptune_db_cluster_parameter_group.id
  port = var.db_cluster_port
  iam_roles = local.AttachBulkloadIAMRoleToNeptuneClusterCondition ? [
    {
      RoleArn = aws_iam_role.neptune_load_from_s3_role.arn
    }
  ] : null
  storage_encrypted = var.storage_encrypted
}

resource "aws_neptune_cluster_instance" "neptune_db_instance" {
  cluster_identifier = aws_neptune_cluster.neptune_db_cluster.arn
  instance_class = var.db_instance_type
  neptune_parameter_group_name = aws_neptune_parameter_group.neptune_db_parameter_group.id
}

resource "aws_neptune_cluster_instance" "neptune_db_replica_instance" {
  count = local.CreateDBReplicaInstance ? 1 : 0
  identifier = "${aws_neptune_cluster_instance.neptune_db_instance.address}-${var.db_replica_identifier_suffix}"
  cluster_identifier = aws_neptune_cluster.neptune_db_cluster.arn
  instance_class = var.db_instance_type
}

resource "aws_ssm_parameter" "neptune_db_cluster_id_ssm" {
  name = "/multimodalapp/${var.environment_name}/NeptuneDBClusterEndpoint"
  type = "String"
  value = aws_neptune_cluster.neptune_db_cluster.endpoint
  description = "SSM Parameter for Neptune DB Cluster Endpoint"
  allowed_pattern = ".*"
}

resource "aws_ssm_parameter" "neptune_load_from_s3_role_ssm" {
  name = "/multimodalapp/${var.environment_name}/NeptuneDBS3RoleArn"
  type = "String"
  value = aws_iam_role.neptune_load_from_s3_role.arn
  description = "SSM Parameter for Neptune DB S3 Role"
  allowed_pattern = ".*"
}

resource "aws_ssm_parameter" "neptune_sgssm" {
  name = "/multimodalapp/${var.environment_name}/NeptuneSG"
  type = "String"
  value = aws_security_group.neptune_sg.arn
  description = "SSM Parameter for Neptune Security Group"
  allowed_pattern = ".*"
}

resource "aws_ssm_parameter" "neptune_cluster_port_ssm" {
  name = "/multimodalapp/${var.environment_name}/NeptuneDBClusterPort"
  type = "String"
  value = aws_neptune_cluster.neptune_db_cluster.port
  description = "SSM Parameter for Neptune DB Cluster Port"
  allowed_pattern = ".*"
}

output "neptune_db_cluster_id" {
  description = "Neptune Cluster Identifier"
  value = aws_neptune_cluster.neptune_db_cluster.arn
}

output "neptune_db_subnet_group_id" {
  description = "Neptune DBSubnetGroup Identifier"
  value = aws_neptune_subnet_group.neptune_db_subnet_group.id
}

output "neptune_db_cluster_resource_id" {
  description = "Neptune Cluster Resource Identifier"
  value = aws_neptune_cluster.neptune_db_cluster.cluster_resource_id
}

output "neptune_db_cluster_endpoint" {
  description = "Master Endpoint for Neptune Cluster"
  value = aws_neptune_cluster.neptune_db_cluster.endpoint
}

output "neptune_db_instance_endpoint" {
  description = "Master Instance Endpoint"
  value = aws_neptune_cluster_instance.neptune_db_instance.endpoint
}

output "neptune_db_replica_instance_endpoint" {
  description = "ReadReplica Instance Endpoint"
  value = aws_neptune_cluster_instance.neptune_db_replica_instance.endpoint
}

output "neptune_sparql_endpoint" {
  description = "Sparql Endpoint for Neptune"
  value = "https://${aws_neptune_cluster.neptune_db_cluster.endpoint}:${aws_neptune_cluster.neptune_db_cluster.port}/sparql"
}

output "neptune_db_cluster_read_endpoint" {
  description = "DB cluster Read Endpoint"
  value = aws_neptune_cluster.neptune_db_cluster.endpoint
}

output "neptune_db_cluster_port" {
  description = "Port for the Neptune Cluster"
  value = aws_neptune_cluster.neptune_db_cluster.port
}

output "neptune_sg" {
  description = "NeptuneSG"
  value = aws_security_group.neptune_sg.arn
}
