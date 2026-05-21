#!/bin/bash
set -euo pipefail

CONTENT_IP="__CONTENT_IP__"
BUCKET="__BUCKET__"

LOG_FILE="/tmp/bastion_day2.log"

# Redirect stdout and stderr to log file
exec > >(tee -i $LOG_FILE) 2>&1

echo "=========================================="
echo "   Bastion - Day 2 Background Automation  "
echo "   Started at: $(date)"
echo "=========================================="

# -------------------------------------------------------------
# PHASE 1: Copy ISO from GDrive to S3 via Bastion (Idempotent)
# -------------------------------------------------------------
echo "=> [Phase 1] Checking if ISO is already in S3..."
if aws s3 ls "s3://${BUCKET}/status/UPLOAD_DONE.flag" >/dev/null 2>&1; then
    echo "   [SKIP] ISO already uploaded and verified in S3."
else
    echo "   [RUN] Setting up rclone config..."
    mkdir -p ~/.config/rclone && mv /tmp/rclone.conf ~/.config/rclone/rclone.conf 2>/dev/null || true
    
    echo "   [RUN] Starting rclone copy (Google Drive -> S3)..."
    rclone copy "gdrive:rhel/rhel-9.7-x86_64-dvd.iso" ":s3:${BUCKET}/iso/" --s3-env-auth --s3-region ap-southeast-1 --s3-location-constraint ap-southeast-1 --s3-no-check-bucket --progress --s3-upload-concurrency 4
    
    echo "   [RUN] Validating Checksum..."
    aws s3 cp "s3://${BUCKET}/iso/rhel-9.7-x86_64-dvd.iso" /tmp/rhel-check.iso --no-progress
    SHA_SUM=$(sha256sum /tmp/rhel-check.iso | awk '{print $1}')
    echo "${SHA_SUM}" > /tmp/rhel.sha256
    aws s3 cp /tmp/rhel.sha256 "s3://${BUCKET}/iso/rhel-9.7-x86_64-dvd.iso.sha256"
    rm -f /tmp/rhel-check.iso /tmp/rhel.sha256
    touch /tmp/flag && aws s3 cp /tmp/flag "s3://${BUCKET}/status/UPLOAD_DONE.flag" && rm -f /tmp/flag
    echo "   [SUCCESS] ISO Phase 1 Upload Complete."
fi

# -------------------------------------------------------------
# PHASE 2: Configure Content Server Local Yum Repo (Idempotent)
# -------------------------------------------------------------
echo "=> [Phase 2] Checking Content Server status..."
SSH_OPTS="-i ~/.ssh/id_ed25519 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o ServerAliveInterval=60 -o ServerAliveCountMax=10"

until ssh ${SSH_OPTS} ec2-user@${CONTENT_IP} "exit" 2>/dev/null; do
    echo "   Waiting for Content Server SSH..."
    sleep 10
done

echo "=> Waiting for Content Server cloud-init to complete..."
ssh ${SSH_OPTS} ec2-user@${CONTENT_IP} "sudo cloud-init status --wait"

if ssh ${SSH_OPTS} ec2-user@${CONTENT_IP} "mount | grep /var/www/html/rhel9" 2>/dev/null; then
     echo "   [SKIP] ISO is already mounted on Content Server."
else
     echo "   [RUN] Copying setup script to Content Server..."
     scp ${SSH_OPTS} /tmp/setup_content.sh ec2-user@${CONTENT_IP}:/tmp/setup_content.sh
     
     echo "   [RUN] Executing setup script on Content Server..."
     ssh ${SSH_OPTS} ec2-user@${CONTENT_IP} "chmod +x /tmp/setup_content.sh && /tmp/setup_content.sh"
     echo "   [SUCCESS] ISO Phase 2 Setup Complete."
fi

echo "=========================================="
echo " Background Automation Completed!"
echo " Finished at: $(date)"
echo "=========================================="
