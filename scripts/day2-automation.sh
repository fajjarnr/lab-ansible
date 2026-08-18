#!/bin/bash
set -euo pipefail

BASTION_IP=$1
CONTENT_IP=$2

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
# PREPARATION: Generate and Transfer Scripts
# -------------------------------------------------------------
echo "=> Generating automation scripts..."

SCRIPT_DIR="$(dirname "$0")"
mkdir -p "$SCRIPT_DIR/.generated"

# Copy setup_content.sh
cp "$SCRIPT_DIR/setup_content.sh.tpl" "$SCRIPT_DIR/.generated/setup_content.sh"

# Generate bastion_day2.sh
sed "s/__CONTENT_IP__/$CONTENT_IP/g" "$SCRIPT_DIR/bastion_day2.sh.tpl" > "$SCRIPT_DIR/.generated/bastion_day2.sh"

echo "=> Transferring configurations and scripts to Bastion..."
# Transfer SSH Private Key to Bastion so it can connect to Content Server
scp $SSH_OPTS ~/.ssh/id_ed25519 ec2-user@$BASTION_IP:~/.ssh/id_ed25519
ssh $SSH_OPTS ec2-user@$BASTION_IP "chmod 600 ~/.ssh/id_ed25519"

# Transfer scripts
scp $SSH_OPTS "$SCRIPT_DIR/.generated/setup_content.sh" ec2-user@$BASTION_IP:/tmp/setup_content.sh
scp $SSH_OPTS "$SCRIPT_DIR/.generated/bastion_day2.sh" ec2-user@$BASTION_IP:/tmp/bastion_day2.sh
ssh $SSH_OPTS ec2-user@$BASTION_IP "chmod +x /tmp/bastion_day2.sh"

# Clean up local generated files
rm -rf "$SCRIPT_DIR/.generated"

# -------------------------------------------------------------
# LAUNCH BACKGROUND JOB ON BASTION
# -------------------------------------------------------------
echo "=> Launching Day-2 Automation in background on Bastion..."
ssh $SSH_OPTS ec2-user@$BASTION_IP "nohup /tmp/bastion_day2.sh > /tmp/bastion_day2.log 2>&1 < /dev/null &"

# Let's pause for a second to let it start and verify it launched
sleep 2
if ssh $SSH_OPTS ec2-user@$BASTION_IP "pgrep -f bastion_day2.sh" >/dev/null; then
    echo "   [SUCCESS] Background process successfully started on Bastion!"
else
    echo "   [ERROR] Failed to start background process on Bastion. Please check Bastion logs."
    exit 1
fi

echo "======================================================================="
echo "  Day-2 Automation is now running in the background on the Bastion!"
echo "  You can safely close this terminal or let Terraform finish."
echo "  "
echo "  To monitor the real-time progress, run the following command:"
echo "  ssh -i ~/.ssh/id_ed25519 ec2-user@$BASTION_IP \"tail -f /tmp/bastion_day2.log\""
echo "======================================================================="
