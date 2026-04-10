# ──────────────────────────────────────────────
# Target Servers — Ansible Managed Nodes
# ──────────────────────────────────────────────
locals {
  target_servers = {
    servera = { ip = "172.25.250.10" }
    serverb = { ip = "172.25.250.11" }
    serverc = { ip = "172.25.250.12" }
    serverd = { ip = "172.25.250.13" }
  }
}

resource "aws_instance" "target" {
  for_each = local.target_servers

  ami                    = data.aws_ami.rhel.id
  instance_type          = "t3.medium"
  subnet_id              = aws_subnet.private.id
  private_ip             = each.value.ip
  vpc_security_group_ids = [aws_security_group.target_servers.id]
  key_name               = aws_key_pair.lab.key_name

  user_data = templatefile("${path.module}/scripts/target-userdata.sh.tpl", {
    hostname   = each.key
    domain     = var.domain
    content_ip = "172.25.250.254"
  })

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  tags = { Name = "lab-${each.key}" }

  depends_on = [aws_route.private_nat]
}
