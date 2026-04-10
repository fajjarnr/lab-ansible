# ──────────────────────────────────────────────
# Outputs
# ──────────────────────────────────────────────

output "bastion_public_ip" {
  description = "Bastion host public IP (Elastic IP)"
  value       = aws_eip.bastion.public_ip
}

output "bastion_ssh_command" {
  description = "SSH command to connect to bastion"
  value       = "ssh -i ~/.ssh/id_ed25519 ec2-user@${aws_eip.bastion.public_ip}"
}

output "content_server_ip" {
  description = "Content server private IP"
  value       = aws_instance.content_server.private_ip
}

output "content_server_ssh_via_bastion" {
  description = "SSH to content server via bastion (ProxyJump)"
  value       = "ssh -i ~/.ssh/id_ed25519 -J ec2-user@${aws_eip.bastion.public_ip} ec2-user@172.25.250.254"
}

output "target_server_ips" {
  description = "Target server private IPs"
  value = {
    for name, instance in aws_instance.target : name => instance.private_ip
  }
}

output "s3_bucket_name" {
  description = "S3 bucket name for ISO storage"
  value       = aws_s3_bucket.lab.bucket
}

output "rhel_ami_id" {
  description = "RHEL 9.7 AMI ID used"
  value       = data.aws_ami.rhel.id
}

output "admin_ip_detected" {
  description = "Auto-detected admin IP (used for bastion SG)"
  value       = local.admin_cidr
}

output "inventory_file" {
  description = "Path to generated Ansible inventory"
  value       = local_file.ansible_inventory.filename
}
