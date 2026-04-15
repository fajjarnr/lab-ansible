resource "aws_instance" "content_server" {
  ami                    = data.aws_ami.rhel.id
  instance_type          = "t3.large"
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.content_server.id]
  key_name               = aws_key_pair.lab.key_name
  iam_instance_profile   = aws_iam_instance_profile.content_server.name

  user_data = templatefile("${path.module}/scripts/content-server-userdata.sh.tpl", {
    domain       = var.domain
    target_hosts = local.target_names # Pass only names, or empty
  })

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
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
  filename        = "${path.module}/playbooks/inventory/hosts.ini"
  file_permission = "0644"

  content = <<-EOT
    [control]
    content.${var.domain} ansible_host=${aws_instance.content_server.private_ip}

    [managed]
    $${join("\n", [for name in local.target_names : "$${name}.$${var.domain} ansible_host=$${aws_instance.target[name].private_ip}"])}
  EOT
}
