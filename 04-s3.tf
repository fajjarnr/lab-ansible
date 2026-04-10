# ──────────────────────────────────────────────
# S3 Bucket with random suffix for uniqueness
# ──────────────────────────────────────────────
resource "random_id" "bucket_suffix" {
  byte_length = 3 # Produces 5-6 hex characters
}

resource "aws_s3_bucket" "lab" {
  bucket        = "lab-ansible-${random_id.bucket_suffix.hex}"
  force_destroy = true # Easy cleanup for lab environment

  tags = { Name = "lab-ansible-bucket" }
}

resource "aws_s3_bucket_versioning" "lab" {
  bucket = aws_s3_bucket.lab.id
  versioning_configuration {
    status = "Suspended"
  }
}

resource "aws_s3_bucket_public_access_block" "lab" {
  bucket = aws_s3_bucket.lab.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
