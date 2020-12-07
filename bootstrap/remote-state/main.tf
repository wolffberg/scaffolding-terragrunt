terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
}

provider "aws" {}

resource "aws_s3_bucket" "this" {
  bucket = "${var.repository_name}-remote-state"
  acl    = "private"

  tags = {
    Name = var.repository_name
  }
}

resource "aws_dynamodb_table" "this" {
  name     = "${var.repository_name}-remote-state"
  hash_key = "LockID"
  read_capacity  = 5
  write_capacity = 5

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name = "${var.repository_name}-remote-state"
  }
}

data "aws_iam_policy_document" "this" {
  statement {
    sid = "S3ListBucket"

    actions = [
      "s3:ListBucket",
    ]

    resources = [
      aws_s3_bucket.this.arn
    ]
  }

  statement {
    sid = "S3ReadWrite"

    actions = [
      "s3:*Object",
    ]

    resources = [
      "${aws_s3_bucket.this.arn}/*"
    ]
  }

  statement {
    sid = "DynamoDBReadWrite"

    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:DeleteItem"
    ]

    resources = [
      aws_dynamodb_table.this.arn
    ]
  }
}

resource "aws_iam_policy" "this" {
  name   = "${var.repository_name}RemoteStateReadWrite"
  path   = "/${var.repository_name}/"
  policy = data.aws_iam_policy_document.this.json
}
