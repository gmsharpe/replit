provider "aws" { region = "us-west-2" }

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

resource "aws_iam_policy" "bedrock_invoke_policy" {
  name        = "BedrockInvokePolicy"
  description = "Policy to allow invoking Bedrock models"
  policy      = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream"
        ],
        Resource = "arn:aws:bedrock:*::foundation-model/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "attach_bedrock_invoke_policy" {
  role       = aws_iam_role.sagemaker_execution_role.name
  policy_arn = aws_iam_policy.bedrock_invoke_policy.arn
}

resource "aws_sagemaker_notebook_instance" "sagemaker_notebook" {
  name              = "sagemaker-notebook-${random_string.suffix.id}"
  instance_type     = "ml.t3.medium"
  role_arn          = aws_iam_role.sagemaker_execution_role.arn

}

output "sagemaker_notebook_name" {
  value = aws_sagemaker_notebook_instance.sagemaker_notebook.name
}

# output "sagemaker_notebook_url" {
#   value = aws_sagemaker_notebook_instance.sagemaker_notebook.url
# }