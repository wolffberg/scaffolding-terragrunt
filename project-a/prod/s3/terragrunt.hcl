include {
  path = find_in_parent_folders()
}

terraform {
  source = "github.com/terraform-aws-modules/terraform-aws-s3-bucket?ref=v1.16.0"
}

inputs = {
  bucket_prefix = "s3-"
  acl           = "private"
  force_destroy = true
}
