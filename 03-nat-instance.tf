# ──────────────────────────────────────────────
# NAT Instance (Amazon Linux 2023 + iptables)
# Cost-effective alternative to NAT Gateway (~$3-5/mo vs ~$32/mo)
# ──────────────────────────────────────────────
resource "aws_instance" "nat" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t3.nano"
  subnet_id              = aws_subnet.public.id
  source_dest_check      = false # Required for NAT
  vpc_security_group_ids = [aws_security_group.nat.id]
  key_name               = aws_key_pair.lab.key_name

  user_data = templatefile("${path.module}/scripts/nat-userdata.sh.tpl", {
    private_cidr = var.private_subnet_cidr
  })

  root_block_device {
    volume_size = 8
    volume_type = "gp3"
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tags = { Name = "lab-nat-instance" }

  depends_on = [aws_route.public_internet]
}

# Private subnet default route → NAT instance
resource "aws_route" "private_nat" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = aws_instance.nat.primary_network_interface_id
}
