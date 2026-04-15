#!/bin/bash
set -euo pipefail

BASTION_IP=$1
CONTENT_IP=$2
BUCKET=$3

SSH_OPTS="-i ~/.ssh/id_ed25519 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o ServerAliveInterval=60 -o ServerAliveCountMax=10"

echo "=========================================="
echo "    Ansible Lab - Day 2 Automation        "
echo "=========================================="

echo "=> Waiting for Bastion SSH to become ready..."
until ssh $SSH_OPTS ec2-user@$BASTION_IP "exit" 2>/dev/null; do
    echo "   Retrying in 10s..."
    sleep 10
done

echo "=> Waiting for Bastion cloud-init to complete..."
ssh $SSH_OPTS ec2-user@$BASTION_IP "sudo cloud-init status --wait"

# -------------------------------------------------------------
# PHASE 1: Copy ISO from GDrive to S3 via Bastion (Idempotent)
# -------------------------------------------------------------
echo "=> [Phase 1] Checking if ISO is already in S3..."
if ssh $SSH_OPTS ec2-user@$BASTION_IP "aws s3 ls s3://$BUCKET/status/UPLOAD_DONE.flag" 2>/dev/null; then
    echo "   [SKIP] ISO already uploaded and verified in S3."
else
    echo "   [RUN] Pushing rclone config from local to Bastion..."
    scp $SSH_OPTS ~/.config/rclone/rclone.conf ec2-user@$BASTION_IP:/tmp/rclone.conf || true
    
    echo "   [RUN] Starting upload process on Bastion..."
    ssh $SSH_OPTS ec2-user@$BASTION_IP "cat << 'EOF' > /tmp/upload_iso.sh
#!/bin/bash
set -euo pipefail
mkdir -p ~/.config/rclone && mv /tmp/rclone.conf ~/.config/rclone/rclone.conf 2>/dev/null || true
echo \"Uploading ISO...\"
rclone copy \"gdrive:rhel/rhel-9.7-x86_64-dvd.iso\" \":s3:$BUCKET/iso/\" --s3-env-auth --s3-region ap-southeast-1 --s3-location-constraint ap-southeast-1 --s3-no-check-bucket --progress --s3-upload-concurrency 4
echo \"Validating Checksum...\"
aws s3 cp \"s3://$BUCKET/iso/rhel-9.7-x86_64-dvd.iso\" /tmp/rhel-check.iso --no-progress
SHA_SUM=\$(sha256sum /tmp/rhel-check.iso | awk '{print \$1}')
echo \"\$SHA_SUM\" > /tmp/rhel.sha256
aws s3 cp /tmp/rhel.sha256 \"s3://$BUCKET/iso/rhel-9.7-x86_64-dvd.iso.sha256\"
rm -f /tmp/rhel-check.iso /tmp/rhel.sha256
touch /tmp/flag && aws s3 cp /tmp/flag \"s3://$BUCKET/status/UPLOAD_DONE.flag\" && rm -f /tmp/flag
EOF"
    ssh $SSH_OPTS ec2-user@$BASTION_IP "chmod +x /tmp/upload_iso.sh && /tmp/upload_iso.sh"
    echo "   [SUCCESS] ISO Phase 1 Upload Complete."
fi


# -------------------------------------------------------------
# PHASE 2: Configure Content Server Local Yum Repo (Idempotent)
# -------------------------------------------------------------
echo "=> [Phase 2] Checking Content Server status..."
until ssh $SSH_OPTS -J ec2-user@$BASTION_IP ec2-user@$CONTENT_IP "exit" 2>/dev/null; do
    echo "   Waiting for Content Server SSH..."
    sleep 10
done

echo "=> Waiting for Content Server cloud-init to complete..."
ssh $SSH_OPTS -J ec2-user@$BASTION_IP ec2-user@$CONTENT_IP "sudo cloud-init status --wait"

if ssh $SSH_OPTS -J ec2-user@$BASTION_IP ec2-user@$CONTENT_IP "mount | grep /var/www/html/rhel9" 2>/dev/null; then
     echo "   [SKIP] ISO is already mounted on Content Server."
else
     echo "   [RUN] Executing ISO download and mount on Content Server..."
     ssh $SSH_OPTS -J ec2-user@$BASTION_IP ec2-user@$CONTENT_IP "cat << 'EOF' > /tmp/setup_content.sh
#!/bin/bash
set -euo pipefail
ISO_DIR=\"/mnt/iso_data\"
ISO_PATH=\"\$ISO_DIR/rhel-9.7-x86_64-dvd.iso\"
MOUNT_DIR=\"/var/www/html/rhel9\"

echo \"Installing AWS CLI...\"
sudo dnf install -y unzip
curl -s \"https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip\" -o \"awscliv2.zip\"
unzip -qo awscliv2.zip
sudo ./aws/install --update
rm -rf aws awscliv2.zip

echo \"Downloading ISO and Sha256 from S3...\"
sudo /usr/local/bin/aws s3 cp \"s3://$BUCKET/iso/rhel-9.7-x86_64-dvd.iso\" \"\$ISO_PATH\"
sudo /usr/local/bin/aws s3 cp \"s3://$BUCKET/iso/rhel-9.7-x86_64-dvd.iso.sha256\" \"/tmp/rhel.sha256\"

echo \"Verifying checksum...\"
EXPECTED=\$(cat /tmp/rhel.sha256)
ACTUAL=\$(sha256sum \"\$ISO_PATH\" | awk '{print \$1}')
if [ \"\$EXPECTED\" != \"\$ACTUAL\" ]; then
    echo \"ERROR: Checksum mismatch! Expected \$EXPECTED but got \$ACTUAL\"
    exit 1
fi
echo \"Checksum valid!\"

echo \"Setting up systemd mount...\"
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

sudo mkdir -p \"\$MOUNT_DIR\"
sudo systemctl daemon-reload
sudo systemctl enable --now var-www-html-rhel9.mount
echo \"Local YUM Repo ready!\"
EOF"
     ssh $SSH_OPTS -J ec2-user@$BASTION_IP ec2-user@$CONTENT_IP "chmod +x /tmp/setup_content.sh && /tmp/setup_content.sh"
     echo "   [SUCCESS] ISO Phase 2 Setup Complete."
fi
echo "=========================================="
echo " Automation Completed!"
echo "=========================================="
