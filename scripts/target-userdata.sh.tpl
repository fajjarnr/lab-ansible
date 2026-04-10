#!/bin/bash
set -euo pipefail
exec > >(tee /var/log/userdata.log) 2>&1

echo "=== Target Server ${hostname} Bootstrap ==="

# ── Hostname ──
hostnamectl set-hostname "${hostname}.${domain}"

# ── Time sync ──
systemctl enable --now chronyd
chronyc makestep

# ── /etc/hosts fallback ──
if ! grep -q "content.${domain}" /etc/hosts; then
  echo "${content_ip} content.${domain} content" >> /etc/hosts
fi

# ── SSH hardening ──
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
systemctl restart sshd

echo "=== Target Server ${hostname} Bootstrap Complete ==="
