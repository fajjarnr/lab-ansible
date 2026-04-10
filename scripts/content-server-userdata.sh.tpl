#!/bin/bash
set -euo pipefail
exec > >(tee /var/log/userdata.log) 2>&1

echo "=== Content Server Bootstrap ==="

# ── Hostname ──
hostnamectl set-hostname "content.${domain}"

# ── Time sync ──
systemctl enable --now chronyd
chronyc makestep

# ── SSH hardening ──
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
systemctl restart sshd

# ── /etc/hosts fallback (before Route53 propagation) ──
cat >> /etc/hosts <<'HOSTSEOF'
${content_ip} content.${domain} content
%{for name, server in target_hosts~}
${server.ip} ${name}.${domain} ${name}
%{endfor~}
HOSTSEOF

# ── Dynamic disk discovery & format ──
echo "Waiting for data disk to appear..."
DATA_DISK=""
for i in $(seq 1 30); do
  DATA_DISK=$(lsblk -d -n -o NAME,SIZE | grep '20G' | awk '{print $1}' | head -1)
  if [ -n "$DATA_DISK" ]; then
    break
  fi
  echo "Attempt $i/30: Data disk not found yet, waiting 10s..."
  sleep 10
done

if [ -z "$DATA_DISK" ]; then
  echo "ERROR: Data disk 20GB not found after 5 minutes!" >&2
  # Continue without data disk — don't block entire bootstrap
  echo "WARNING: Proceeding without data disk. Mount manually later."
else
  echo "Data disk detected: /dev/$DATA_DISK"

  # Format only if no filesystem exists (idempotent)
  if ! blkid "/dev/$DATA_DISK" 2>/dev/null | grep -q 'xfs'; then
    mkfs.xfs -f "/dev/$DATA_DISK"
    echo "Disk formatted as XFS."
  else
    echo "Filesystem XFS already exists — skip mkfs."
  fi

  mkdir -p /mnt/iso_data
  if ! grep -q '/mnt/iso_data' /etc/fstab; then
    echo "/dev/$DATA_DISK /mnt/iso_data xfs defaults,noatime 0 0" >> /etc/fstab
  fi
  mount -a
  echo "Data disk mounted at /mnt/iso_data."
fi

# ── Install packages from default RHEL repos (via NAT) ──
dnf install -y httpd ansible-core python3-pip
pip3 install boto3 botocore 2>/dev/null || true

# ── Install amazon.aws Ansible collection ──
ansible-galaxy collection install amazon.aws

# ── Firewall ──
systemctl enable --now firewalld
firewall-cmd --permanent --add-service=http
firewall-cmd --reload

# ── Start httpd ──
mkdir -p /var/www/html/rhel9
systemctl enable --now httpd

# ── Ansible inventory directory ──
mkdir -p /etc/ansible/inventory

# ── Logrotate — prevent disk full ──
cat > /etc/logrotate.d/lab-logs <<'LOGEOF'
/var/log/httpd/*log /var/log/ansible/*.log {
    daily
    rotate 3
    compress
    missingok
    notifempty
}
LOGEOF

echo "=== Content Server Bootstrap Complete ==="
