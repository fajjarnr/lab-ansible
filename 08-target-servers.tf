# ──────────────────────────────────────────────
# Target Servers — Ansible Managed Nodes
# ──────────────────────────────────────────────
locals {
  target_names = ["servera", "serverb", "serverc", "serverd"]
}

resource "aws_instance" "target" {
  for_each = toset(local.target_names)

  ami                    = data.aws_ami.rhel.id
  instance_type          = "t3.medium"
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.target_servers.id]
  key_name               = aws_key_pair.lab.key_name

  user_data = templatefile("${path.module}/scripts/target-userdata.sh.tpl", {
    hostname   = each.key
    domain     = var.domain
    content_ip = aws_instance.content_server.private_ip
  })

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tags = { Name = "lab-${each.key}" }

  depends_on = [aws_route.private_nat]
}
