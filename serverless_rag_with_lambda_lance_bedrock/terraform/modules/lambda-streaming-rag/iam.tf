
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.document_processor_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_policy" "document_processor_policy" {
  name        = "document-processor-policy"
  description = "IAM policy for the Lambda function"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["bedrock:InvokeModel"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:List*","s3:DeleteObject"]
        Resource = [
          "${aws_s3_bucket.document_bucket.arn}/*",
          aws_s3_bucket.document_bucket.arn
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "document_processor_attachment" {
  role       = aws_iam_role.document_processor_role.name
  policy_arn = aws_iam_policy.document_processor_policy.arn
}
