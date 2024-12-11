provider "aws" { region = "us-west-1" }

resource "aws_s3_bucket" "sagemaker_bucket" {
  bucket = "my-sagemaker-notebook-bucket-${random_string.suffix.id}"
  acl    = "private"
  versioning {
    enabled = true
  }
}

resource "random_string" "suffix" {
  length  = 6
  special = false
}

resource "aws_iam_role" "sagemaker_execution_role" {
  name = "SageMakerExecutionRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action    = "sts:AssumeRole",
        Effect    = "Allow",
        Principal = {
          Service = "sagemaker.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "sagemaker_policy" {
  role       = aws_iam_role.sagemaker_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess"
}

resource "aws_sagemaker_notebook_instance" "sagemaker_notebook" {
  name              = "sagemaker-notebook-${random_string.suffix.id}"
  instance_type     = "ml.t2.medium"
  role_arn          = aws_iam_role.sagemaker_execution_role.arn

  lifecycle_config_name = aws_sagemaker_notebook_instance_lifecycle_configuration.lifecycle_config.name
}

resource "aws_sagemaker_notebook_instance_lifecycle_configuration" "lifecycle_config" {
  name = "sagemaker-notebook-lifecycle-config"

  on_create = <<EOT
#!/bin/bash
set -e

# Custom initialization logic can go here
EOT

  on_start = <<EOT
#!/bin/bash
set -e

# Custom startup logic can go here
EOT
}

output "sagemaker_bucket_name" {
  value = aws_s3_bucket.sagemaker_bucket.bucket
}

output "sagemaker_notebook_name" {
  value = aws_sagemaker_notebook_instance.sagemaker_notebook.name
}