# ──────────────────────────────────────────────
# Bastion Host — SSH gateway + ISO upload executor
# ──────────────────────────────────────────────
resource "aws_instance" "bastion" {
  ami                    = data.aws_ami.rhel.id
  instance_type          = "t3.large"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.bastion.id]
  key_name               = aws_key_pair.lab.key_name
  iam_instance_profile   = aws_iam_instance_profile.bastion.name

  user_data = templatefile("${path.module}/scripts/bastion-userdata.sh.tpl", {
    domain = var.domain
  })

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tags = { Name = "lab-bastion" }

  lifecycle {
    precondition {
      condition     = data.aws_ami.rhel.id != ""
      error_message = "RHEL 9.7 AMI not found in ${var.aws_region}. Verify AMI filter."
    }
  }

  depends_on = [aws_route.public_internet]
}

# Elastic IP for stable bastion endpoint
resource "aws_eip" "bastion" {
  instance = aws_instance.bastion.id
  domain   = "vpc"

  tags = { Name = "lab-bastion-eip" }

  depends_on = [aws_internet_gateway.lab]
}
