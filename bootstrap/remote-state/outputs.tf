output "s3_bucket_id" {
  value = aws_s3_bucket.this.id
}

output "dynamodb_table_id" {
  value = aws_dynamodb_table.this.id
}

output "iam_role_arn" {
  value = aws_iam_role.this.arn
}
