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

# -------------------------------------------------------------
# PHASE 2: Configure Local Yum Repo on Bastion (Idempotent)
# -------------------------------------------------------------
echo "=> [Phase 2] Configuring Local Yum Repo on Bastion..."

# Backup existing RHUI repos if present
if ls /etc/yum.repos.d/redhat-rhui*.repo >/dev/null 2>&1; then
    echo "   Backing up existing RHUI repos..."
    sudo mkdir -p /etc/yum.repos.d/backup
    sudo mv /etc/yum.repos.d/redhat-rhui*.repo /etc/yum.repos.d/backup/ 2>/dev/null || true
fi

echo "   Writing /etc/yum.repos.d/local-rhel9.repo..."
sudo tee /etc/yum.repos.d/local-rhel9.repo > /dev/null << REPOEOF
[local-baseos]
name=RHEL 9.8 BaseOS - Local Mirror
baseurl=http://${CONTENT_IP}/rhel9/BaseOS
gpgcheck=0
enabled=1
sslverify=0

[local-appstream]
name=RHEL 9.8 AppStream - Local Mirror
baseurl=http://${CONTENT_IP}/rhel9/AppStream
gpgcheck=0
enabled=1
sslverify=0
REPOEOF

echo "=> Testing Bastion repository access..."
sudo dnf clean all
sudo dnf repolist
echo "   [SUCCESS] Bastion Local Yum Repo configured."

echo "=========================================="
echo " Background Automation Completed!"
echo " Finished at: $(date)"
echo "=========================================="
