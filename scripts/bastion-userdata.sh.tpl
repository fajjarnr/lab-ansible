#!/bin/bash
set -euo pipefail
exec > >(tee /var/log/userdata.log) 2>&1

echo "=== Bastion Bootstrap ==="

# Hostname
hostnamectl set-hostname "bastion.${domain}"

# SSH hardening — no root login, no password auth
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
systemctl restart sshd

# Time sync (required for AWS API calls and Ansible)
systemctl enable --now chronyd
chronyc makestep

# Install AWS CLI v2
curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
dnf install -y unzip
cd /tmp && unzip -qo awscliv2.zip
/tmp/aws/install --update
rm -rf /tmp/aws /tmp/awscliv2.zip

# Install rclone (for GDrive → S3 ISO transfer)
curl -sO https://downloads.rclone.org/current/rclone-current-linux-amd64.rpm
dnf install -y ./rclone-current-linux-amd64.rpm
rm -f rclone-current-linux-amd64.rpm

echo "=== Bastion Bootstrap Complete ==="
