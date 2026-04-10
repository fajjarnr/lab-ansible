# ──────────────────────────────────────────────
# Common EC2 Assume Role Policy
# ──────────────────────────────────────────────
data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# ──────────────────────────────────────────────
# Bastion IAM Role — S3 upload + SSM read
# ──────────────────────────────────────────────
resource "aws_iam_role" "bastion" {
  name               = "lab-ansible-bastion-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
  tags               = { Name = "lab-ansible-bastion-role" }
}

resource "aws_iam_role_policy" "bastion" {
  name = "lab-ansible-bastion-policy"
  role = aws_iam_role.bastion.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3Access"
        Effect = "Allow"
        Action = [
          "s3:PutObject", 
          "s3:AbortMultipartUpload", 
          "s3:GetObject", 
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.lab.arn,
          "${aws_s3_bucket.lab.arn}/iso/*",
          "${aws_s3_bucket.lab.arn}/status/*"
        ]
      },
      {
        Sid      = "SSMRead"
        Effect   = "Allow"
        Action   = ["ssm:GetParameter"]
        Resource = "arn:aws:ssm:${var.aws_region}:*:parameter/lab/*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "bastion" {
  name = "lab-ansible-bastion-profile"
  role = aws_iam_role.bastion.name
}

# ──────────────────────────────────────────────
# Content Server IAM Role — S3 download + SSM read
# ──────────────────────────────────────────────
resource "aws_iam_role" "content_server" {
  name               = "lab-ansible-content-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
  tags               = { Name = "lab-ansible-content-role" }
}

resource "aws_iam_role_policy" "content_server" {
  name = "lab-ansible-content-policy"
  role = aws_iam_role.content_server.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "S3Download"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:ListBucket"]
        Resource = [aws_s3_bucket.lab.arn, "${aws_s3_bucket.lab.arn}/*"]
      },
      {
        Sid      = "SSMRead"
        Effect   = "Allow"
        Action   = ["ssm:GetParameter"]
        Resource = "arn:aws:ssm:${var.aws_region}:*:parameter/lab/*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "content_server" {
  name = "lab-ansible-content-profile"
  role = aws_iam_role.content_server.name
}
