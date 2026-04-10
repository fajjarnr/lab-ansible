# ──────────────────────────────────────────────
# Content Server — Ansible Control Node + HTTP Repo
# ──────────────────────────────────────────────
resource "aws_instance" "content_server" {
  ami                    = data.aws_ami.rhel.id
  instance_type          = "t3.large"
  subnet_id              = aws_subnet.private.id
  private_ip             = "172.25.250.254"
  vpc_security_group_ids = [aws_security_group.content_server.id]
  key_name               = aws_key_pair.lab.key_name
  iam_instance_profile   = aws_iam_instance_profile.content_server.name

  user_data = templatefile("${path.module}/scripts/content-server-userdata.sh.tpl", {
    domain       = var.domain
    content_ip   = "172.25.250.254"
    target_hosts = local.target_servers
  })

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  tags = { Name = "lab-content-server" }

  depends_on = [aws_route.private_nat]
}

# Separate EBS data disk (Terraform AWS Provider v5+ — no ebs_block_device)
resource "aws_ebs_volume" "content_data" {
  availability_zone = aws_instance.content_server.availability_zone
  size              = 20
  type              = "gp3"

  tags = { Name = "lab-content-data-disk" }
}

resource "aws_volume_attachment" "content_data" {
  device_name  = "/dev/sdf" # AWS remaps to /dev/nvme1n1 on t3
  volume_id    = aws_ebs_volume.content_data.id
  instance_id  = aws_instance.content_server.id
  force_detach = false
}

# ──────────────────────────────────────────────
# Generated Ansible Inventory
# ──────────────────────────────────────────────
resource "local_file" "ansible_inventory" {
  filename        = "${path.module}/inventory/hosts.ini"
  file_permission = "0644"

  content = <<-EOT
    [control]
    content.${var.domain} ansible_host=${aws_instance.content_server.private_ip}

    [managed]
    %{for name, server in local.target_servers~}
    ${name}.${var.domain} ansible_host=${aws_instance.target[name].private_ip}
    %{endfor~}

    [all:vars]
    ansible_user=ec2-user
    ansible_ssh_private_key_file=~/.ssh/id_ed25519
  EOT
}
