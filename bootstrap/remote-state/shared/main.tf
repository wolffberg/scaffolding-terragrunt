terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
}

locals {
  # Try to convert repository name with hyphens into CamcelCase
  camelcase_role_name = try(replace(title(replace(var.repository_name, "-", " ")), " ", ""), var.repository_name)
}

resource "aws_s3_bucket" "this" {
  bucket = "${var.repository_name}-remote-state"

  tags = {
    Name = var.repository_name
  }
}

resource "aws_s3_bucket_acl" "this" {
  bucket = aws_s3_bucket.this.id

  acl = "private"
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    # TODO: Fix this
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# These statements are required as Terragrunt 
# will otherwise try to add it on each apply.
data "aws_iam_policy_document" "s3" {
  statement {
    sid     = "RootAccess"
    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.this.arn
    ]

    principals {
      type        = "AWS"
      identifiers = [data.aws_caller_identity.current.account_id]
    }
  }

  statement {
    sid     = "EnforceSecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.this.arn,
      "${aws_s3_bucket.this.arn}/*"
    ]

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = [false]
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.s3.json
}

resource "aws_dynamodb_table" "this" {
  name           = "${var.repository_name}-remote-state"
  hash_key       = "LockID"
  read_capacity  = 5
  write_capacity = 5

  server_side_encryption {
    enabled = true
  }

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

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "tfstate" {
  statement {
    sid = "S3ListBucket"

    actions = [
      "s3:ListBucket",
      "s3:GetBucketVersioning",
      "s3:GetBucketPublicAccessBlock",
      "s3:GetBucketPolicy"
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
