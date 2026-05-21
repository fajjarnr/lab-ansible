#!/bin/bash
set -euo pipefail
ISO_DIR="/mnt/iso_data"
ISO_PATH="${ISO_DIR}/rhel-9.7-x86_64-dvd.iso"
MOUNT_DIR="/var/www/html/rhel9"

echo "Installing AWS CLI..."
sudo dnf install -y unzip
curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip -qo awscliv2.zip
sudo ./aws/install --update
rm -rf aws awscliv2.zip

echo "Downloading ISO and Sha256 from S3..."
sudo /usr/local/bin/aws s3 cp "s3://__BUCKET__/iso/rhel-9.7-x86_64-dvd.iso" "${ISO_PATH}"
sudo /usr/local/bin/aws s3 cp "s3://__BUCKET__/iso/rhel-9.7-x86_64-dvd.iso.sha256" "/tmp/rhel.sha256"

echo "Verifying checksum..."
EXPECTED=$(cat /tmp/rhel.sha256)
ACTUAL=$(sha256sum "${ISO_PATH}" | awk '{print $1}')
if [ "${EXPECTED}" != "${ACTUAL}" ]; then
    echo "ERROR: Checksum mismatch! Expected ${EXPECTED} but got ${ACTUAL}"
    exit 1
fi
echo "Checksum valid!"

echo "Setting up systemd mount..."
sudo tee /etc/systemd/system/var-www-html-rhel9.mount > /dev/null << 'MOUNT'
[Unit]
Description=Mount RHEL 9.7 ISO
After=local-fs.target mnt-iso_data.mount
Requires=mnt-iso_data.mount

[Mount]
What=/mnt/iso_data/rhel-9.7-x86_64-dvd.iso
Where=/var/www/html/rhel9
Type=iso9660
Options=loop,ro,context=system_u:object_r:httpd_sys_content_t:s0

[Install]
WantedBy=multi-user.target
MOUNT

sudo mkdir -p "${MOUNT_DIR}"
sudo systemctl daemon-reload
sudo systemctl enable --now var-www-html-rhel9.mount
echo "Local YUM Repo ready!"
