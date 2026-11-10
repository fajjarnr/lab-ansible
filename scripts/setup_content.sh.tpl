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
    echo "Downloading Rocky Linux 9.8 DVD ISO (~14GB) via aria2c..."
    if ! command -v aria2c &> /dev/null; then
        echo "Installing aria2 from EPEL..."
        sudo dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm
        sudo dnf install -y aria2
    fi

    sudo aria2c -x 16 -s 16 -k 1M \
        --file-allocation=falloc \
        -c \
        --summary-interval=10 \
        --dir="${ISO_DIR}" \
        --out="$(basename "${ISO_PATH}")" \
        "${ISO_URL}"

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

echo "Configuring local repository for Content Server..."
if ls /etc/yum.repos.d/redhat-rhui*.repo >/dev/null 2>&1; then
    echo "Backing up existing RHUI repos..."
    sudo mkdir -p /etc/yum.repos.d/backup
    sudo mv /etc/yum.repos.d/redhat-rhui*.repo /etc/yum.repos.d/backup/ 2>/dev/null || true
fi

sudo tee /etc/yum.repos.d/local-rhel9.repo > /dev/null << 'REPOEOF'
[local-baseos]
name=RHEL 9.8 BaseOS - Local ISO
baseurl=file:///var/www/html/rhel9/BaseOS
gpgcheck=0
enabled=1
sslverify=0

[local-appstream]
name=RHEL 9.8 AppStream - Local ISO
baseurl=file:///var/www/html/rhel9/AppStream
gpgcheck=0
enabled=1
sslverify=0
REPOEOF

echo "Testing Content Server local repository access..."
sudo dnf clean all
sudo dnf repolist
echo "Content Server local repository configured successfully."
