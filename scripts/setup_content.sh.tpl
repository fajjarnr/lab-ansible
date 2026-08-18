#!/bin/bash
set -euo pipefail
ISO_DIR="/mnt/iso_data"
ISO_PATH="${ISO_DIR}/rocky-9.8-x86_64-dvd.iso"
MOUNT_DIR="/var/www/html/rhel9"
ISO_URL="https://download.rockylinux.org/pub/rocky/9/isos/x86_64/Rocky-9.8-x86_64-dvd.iso"
CHECKSUM_URL="https://download.rockylinux.org/pub/rocky/9/isos/x86_64/Rocky-9.8-x86_64-dvd.iso.CHECKSUM"

echo "Checking if ISO already downloaded and verified..."
if [ -f "${ISO_PATH}" ] && [ -f "${ISO_DIR}/.iso_verified" ]; then
    echo "ISO already downloaded and verified."
else
    echo "Downloading Rocky Linux 9.8 DVD ISO (~14GB)..."
    sudo curl -L -C - --retry 5 --retry-delay 5 -o "${ISO_PATH}" "${ISO_URL}"

    echo "Verifying checksum..."
    EXPECTED=$(curl -sL "${CHECKSUM_URL}" | grep -E '^SHA256' | awk '{print $4}')
    ACTUAL=$(sha256sum "${ISO_PATH}" | awk '{print $1}')
    if [ "${EXPECTED}" != "${ACTUAL}" ]; then
        echo "ERROR: Checksum mismatch! Expected ${EXPECTED} but got ${ACTUAL}"
        exit 1
    fi
    echo "Checksum valid (${ACTUAL})!"
    sudo touch "${ISO_DIR}/.iso_verified"
fi

echo "Setting up systemd mount..."
sudo tee /etc/systemd/system/var-www-html-rhel9.mount > /dev/null << 'MOUNT'
[Unit]
Description=Mount Rocky 9.8 / RHEL 9 DVD ISO
After=local-fs.target mnt-iso_data.mount
Requires=mnt-iso_data.mount

[Mount]
What=/mnt/iso_data/rocky-9.8-x86_64-dvd.iso
Where=/var/www/html/rhel9
Type=iso9660
Options=loop,ro,context=system_u:object_r:httpd_sys_content_t:s0

[Install]
WantedBy=multi-user.target
MOUNT

sudo mkdir -p "${MOUNT_DIR}"
sudo systemctl daemon-reload
sudo systemctl enable --now var-www-html-rhel9.mount
sudo ln -snf "${MOUNT_DIR}" /var/www/html/rhel
echo "Local YUM Repo ready at ${MOUNT_DIR} (and /var/www/html/rhel)!"
