#!/bin/bash
set -euo pipefail
exec > >(tee /var/log/userdata.log) 2>&1

echo "=== Target Server ${hostname} Bootstrap ==="

# ── Hostname ──
hostnamectl set-hostname "${hostname}.${domain}"


# ── /etc/hosts fallback ──
LOCAL_IP=$(hostname -I | awk '{print $1}')
cat >> /etc/hosts <<HOSTSEOF
$LOCAL_IP ${hostname}.${domain} ${hostname}
${content_ip} content.${domain} content
HOSTSEOF



echo "=== Target Server ${hostname} Bootstrap Complete ==="
