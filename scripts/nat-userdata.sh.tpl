#!/bin/bash
set -euo pipefail
exec > >(tee /var/log/userdata.log) 2>&1

echo "=== NAT Instance Bootstrap ==="

# Enable IP forwarding (immediate + persistent)
echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/99-nat.conf
sysctl -w net.ipv4.ip_forward=1

# Install iptables (AL2023)
dnf install -y iptables

# Set up NAT masquerade for private subnet
iptables -t nat -A POSTROUTING -s ${private_cidr} -j MASQUERADE
iptables -A FORWARD -s ${private_cidr} -j ACCEPT
iptables -A FORWARD -d ${private_cidr} -m state --state ESTABLISHED,RELATED -j ACCEPT

# Persist iptables rules
mkdir -p /etc/sysconfig
iptables-save > /etc/sysconfig/iptables

# Create systemd service for persistence across reboots
cat > /etc/systemd/system/nat-forward.service <<'SVCEOF'
[Unit]
Description=NAT IP Forwarding and Masquerade
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -c "sysctl -w net.ipv4.ip_forward=1 && iptables-restore < /etc/sysconfig/iptables"

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload
systemctl enable nat-forward.service
systemctl enable iptables 2>/dev/null || true

echo "=== NAT Instance Bootstrap Complete ==="
