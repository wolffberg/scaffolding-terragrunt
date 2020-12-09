terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
}

provider "aws" {}

locals {
  # Try to convert repository name with hyphens into CamcelCase
  camelcase_role_name = try(replace(title(replace(var.repository_name, "-", " ")), " ", ""), var.repository_name)

  # DynamoDB Table name is reused for the S3 Bucket but is cut to fit the allowed name length if needed
  dynamodb_table_name = "${var.repository_name}-${var.environment_name}-remote-state"

  # Trim S3 Bucket name length below allowed 63 characters
  bucket_name = substr(local.dynamodb_table_name, 0, 63)

  # Allow trusted identities to assume the IAM policy used for managing the remote state
  # Defaults to the current AWS account ID
  trusted_identities = length(var.trusted_identities) > 0 ? var.trusted_identities : [data.aws_caller_identity.current.account_id]
}

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "this" {
  bucket = local.bucket_name
  acl    = "private"

  versioning {
    enabled = true
  }

  tags = {
    Name = var.repository_name
  }
}

resource "aws_dynamodb_table" "this" {
  name           = local.dynamodb_table_name
  hash_key       = "LockID"
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

data "aws_iam_policy_document" "assume" {
  statement {
    actions = [
      "sts:AssumeRole"
    ]

    principals {
      type        = "AWS"
      identifiers = local.trusted_identities
    }
  }
}

data "aws_iam_policy_document" "tfstate" {
  statement {
    sid = "S3ListBucket"

    actions = [
      "s3:ListBucket",
      "s3:GetBucketVersioning"
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
      "dynamodb:DescribeTable",
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
  name   = "${local.camelcase_role_name}RemoteStateReadWrite"
  path   = "/${local.camelcase_role_name}/"
  policy = data.aws_iam_policy_document.tfstate.json
}

resource "aws_iam_role" "this" {
  name               = "${local.camelcase_role_name}RemoteStateReadWrite"
  path               = "/${local.camelcase_role_name}/"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

resource "aws_iam_role_policy_attachment" "this" {
  role       = aws_iam_role.this.id
  policy_arn = aws_iam_policy.this.arn
}
