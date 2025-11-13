provider "aws" {
  region  = "eu-west-1"
}

# Basic test resource: create an S3 bucket
resource "aws_s3_bucket" "test_bucket" {
  bucket = "terraform-test-bucket-${random_id.suffix.hex}"
}

# Add a random suffix so the bucket name is globally unique
resource "random_id" "suffix" {
  byte_length = 4
}