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
}

resource "aws_s3_bucket" "this" {
  bucket = "${var.repository_name}-remote-state"
  acl    = "private"

  tags = {
    Name = var.repository_name
  }
}

resource "aws_dynamodb_table" "this" {
  name           = "${var.repository_name}-remote-state"
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
      identifiers = var.trusted_identities
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
