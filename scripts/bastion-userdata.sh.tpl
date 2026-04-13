#!/bin/bash
set -euo pipefail
exec > >(tee /var/log/userdata.log) 2>&1

echo "=== Bastion Bootstrap ==="

# Hostname
hostnamectl set-hostname "bastion.${domain}"

# Install AWS CLI v2
curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
dnf install -y unzip
cd /tmp && unzip -qo awscliv2.zip
/tmp/aws/install --update
rm -rf /tmp/aws /tmp/awscliv2.zip

# Install rclone (for GDrive → S3 ISO transfer)
curl -sL https://rclone.org/install.sh | bash

echo "=== Bastion Bootstrap Complete ==="
