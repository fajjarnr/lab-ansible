#!/bin/bash
set -euo pipefail

CONTENT_IP="__CONTENT_IP__"

LOG_FILE="/tmp/bastion_day2.log"

# Redirect stdout and stderr to log file
exec > >(tee -i $LOG_FILE) 2>&1

echo "=========================================="
echo "   Bastion - Day 2 Background Automation  "
echo "   Started at: $(date)"
echo "=========================================="

# -------------------------------------------------------------
# PHASE 1: Configure Content Server Local Yum Repo (Idempotent)
# -------------------------------------------------------------
echo "=> [Phase 1] Checking Content Server status..."
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
     echo "   [SUCCESS] Content Server Local Repo Setup Complete."
fi

echo "=========================================="
echo " Background Automation Completed!"
echo " Finished at: $(date)"
echo "=========================================="
