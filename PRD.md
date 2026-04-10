# Product Requirements Document: Automated Enterprise Ansible Lab

**Versi:** 10.0 (Final - Implemented)
**Status:** Completed
**Domain Lab:** `lab.fajjjar.my.id`
**OS Target:** Red Hat Enterprise Linux 9.7

---

## Changelog

| Versi   | Perubahan Utama                                                                                                                                                                                                     |
| ------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 6.0     | Arsitektur dasar, flag-driven pipeline                                                                                                                                                                              |
| 7.0     | Koreksi S3 URI, dynamic disk discovery, SELinux, SSM Secrets, Terraform EBS v5+, timeout flag, inventory mechanism                                                                                                  |
| 8.0     | Perbaikan fstab ISO → systemd mount unit, IAM JSON lengkap, sinkronisasi path inventory, SHA256 validation, SSH key via SSM, `/etc/hosts` fallback, NAT cost mitigation, chrony, cleanup plan                       |
| **9.0** | Perbaikan checksum streaming Bastion, systemd unit escaping `mnt\-iso_data`, Ansible SSM lookup plugin fix, Terraform provisioner race condition, SSH hardening, logrotate, Terraform `precondition` AMI validation |
| **10.0**| Implementasi final yang sukses! Automasi Day-2 via shell script dipadukan null_resource Terraform, perbaikan S3 Gateway Endpoint untuk AL2023 OS, dan perbaikan mount unit systemd. Ansible Playbook 100% SUCCESS. |

---

## 1. Ringkasan Arsitektur Lab

| Komponen               | Lokasi         | Peran                                                                        |
| ---------------------- | -------------- | ---------------------------------------------------------------------------- |
| **S3 Bucket**          | Global         | Penyimpanan ISO. Format: `lab-ansible-[5 angka acak]`                        |
| **Bastion Host**       | Public Subnet  | Gerbang SSH + eksekutor upload ISO ke S3 via rclone                          |
| **Content Server**     | Private Subnet | Ansible Control Node + Local HTTP Repository. OS disk dan Data disk terpisah |
| **Target Servers × 4** | Private Subnet | Managed Nodes: `servera`, `serverb`, `serverc`, `serverd`                    |

---

## 2. Spesifikasi Komputasi, Jaringan & Penyimpanan

### 2.1 Topologi Jaringan

| Parameter      | Nilai             |
| -------------- | ----------------- |
| VPC CIDR       | `172.25.0.0/16`   |
| Public Subnet  | `172.25.254.0/24` |
| Private Subnet | `172.25.250.0/24` |

### 2.2 Alokasi Instance & Storage

| Node               | Instance    | IP Statis                | Storage (EBS gp3)                 |
| ------------------ | ----------- | ------------------------ | --------------------------------- |
| **Bastion Host**   | `t3.large`  | Dinamis (`172.25.254.x`) | Root OS: 30 GB                    |
| **Content Server** | `t3.large`  | `172.25.250.254`         | Root OS: 30 GB · Data Disk: 20 GB |
| **Server A**       | `t3.medium` | `172.25.250.10`          | Root OS: 30 GB                    |
| **Server B**       | `t3.medium` | `172.25.250.11`          | Root OS: 30 GB                    |
| **Server C**       | `t3.medium` | `172.25.250.12`          | Root OS: 30 GB                    |
| **Server D**       | `t3.medium` | `172.25.250.13`          | Root OS: 30 GB                    |

> **Catatan device name:** Terraform mapping menggunakan `/dev/sdf`, AWS meremapping ke `/dev/nvme1n1` pada instance `t3`. Script User Data **wajib** dynamic discovery — jangan hardcode. Lihat Fase 2 Langkah 1.

### 2.3 AMI Target

```
RHEL-9.7.0_HVM-20260303-x86_64-0-Hourly2-GP3
```

> **⚠ Wajib verifikasi sebelum deploy.** AMI ID bersifat region-specific. Tandai sebagai `# TODO: UPDATE_ON_RELEASE` di Terraform. Verifikasi dengan:
>
> ```bash
> aws ec2 describe-images \
>   --owners 309956199498 \
>   --filters 'Name=name,Values=RHEL-9.7*' \
>   --query 'Images[*].[ImageId,Name,CreationDate]' \
>   --region <YOUR_REGION>
> ```

---

## 3. Persyaratan Fungsional (Terraform IaC)

### F1 — Jaringan & Endpoint

- VPC (`172.25.0.0/16`), Public Subnet, Private Subnet
- Internet Gateway (untuk Bastion)
- **NAT Instance** `t3.nano` — lebih hemat dibanding NAT Gateway (~$32/bulan) untuk lab sementara. Lihat Bagian 7.
- **S3 Gateway Endpoint** — policy dibatasi ke bucket lab spesifik, bukan `*`
- Route53 Private Hosted Zone untuk `lab.fajjjar.my.id` — **wajib** diasosiasikan eksplisit ke VPC ID:

```hcl
resource "aws_route53_zone_association" "lab" {
  zone_id = aws_route53_zone.lab.zone_id
  vpc_id  = aws_vpc.lab.id
}
```

> **⚠ Verifikasi kepemilikan domain** `fajjjar.my.id` sebelum konfigurasi Route53 delegation.

### F2 — S3 Bucket

Gunakan `random_id` untuk nama bucket yang dijamin unik:

```hcl
resource "random_id" "bucket_suffix" {
  byte_length = 3   # menghasilkan 5-6 karakter hex
}

resource "aws_s3_bucket" "lab" {
  bucket = "lab-ansible-${random_id.bucket_suffix.hex}"
}
```

### F3 — IAM Roles (Least Privilege)

**Bastion Host:**

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:PutObject", "s3:AbortMultipartUpload"],
      "Resource": [
        "arn:aws:s3:::lab-ansible-*/iso/*",
        "arn:aws:s3:::lab-ansible-*/status/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": ["ssm:GetParameter"],
      "Resource": "arn:aws:ssm:*:*:parameter/lab/*"
    }
  ]
}
```

**Content Server:**

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:ListBucket"],
      "Resource": ["arn:aws:s3:::lab-ansible-*", "arn:aws:s3:::lab-ansible-*/*"]
    },
    {
      "Effect": "Allow",
      "Action": ["ssm:GetParameter"],
      "Resource": "arn:aws:ssm:*:*:parameter/lab/*"
    }
  ]
}
```

### F4 — Storage EBS (Terraform AWS Provider v5+)

> **⚠ `ebs_block_device` deprecated di Provider v5+.** Gunakan resource terpisah:

```hcl
resource "aws_ebs_volume" "content_data" {
  availability_zone = aws_instance.content_server.availability_zone
  size              = 20
  type              = "gp3"
  tags = { Name = "content-server-data-disk" }
}

resource "aws_volume_attachment" "content_data_att" {
  device_name  = "/dev/sdf"    # AWS meremapping ke /dev/nvme1n1
  volume_id    = aws_ebs_volume.content_data.id
  instance_id  = aws_instance.content_server.id
  force_detach = false
}
```

### F5 — Ansible Inventory Otomatis + Provisioner Race Condition Fix

```hcl
resource "local_file" "ansible_inventory" {
  filename = "${path.module}/inventory/hosts.ini"
  content  = <<-EOT
    [control]
    content.lab.fajjjar.my.id ansible_host=${aws_instance.content_server.private_ip}

    [managed]
    servera.lab.fajjjar.my.id ansible_host=${aws_instance.target_a.private_ip}
    serverb.lab.fajjjar.my.id ansible_host=${aws_instance.target_b.private_ip}
    serverc.lab.fajjjar.my.id ansible_host=${aws_instance.target_c.private_ip}
    serverd.lab.fajjjar.my.id ansible_host=${aws_instance.target_d.private_ip}

    [all:vars]
    ansible_user=ec2-user
    ansible_ssh_private_key_file=~/.ssh/lab_key.pem
  EOT
}

resource "null_resource" "push_inventory" {
  depends_on = [local_file.ansible_inventory, aws_instance.content_server]

  provisioner "remote-exec" {
    inline = [
      # Tunggu SSHD benar-benar ready sebelum melanjutkan
      "while [ ! -f /var/run/sshd.pid ]; do sleep 2; done",
      "mkdir -p /etc/ansible/inventory",
    ]
    connection {
      type         = "ssh"
      host         = aws_instance.content_server.private_ip
      user         = "ec2-user"
      private_key  = file("~/.ssh/lab_key.pem")
      timeout      = "10m"
      bastion_host = aws_instance.bastion.public_ip
    }
  }

  provisioner "file" {
    source      = "${path.module}/inventory/hosts.ini"
    destination = "/etc/ansible/inventory/hosts.ini"
    connection {
      type         = "ssh"
      host         = aws_instance.content_server.private_ip
      user         = "ec2-user"
      private_key  = file("~/.ssh/lab_key.pem")
      timeout      = "10m"
      bastion_host = aws_instance.bastion.public_ip
    }
  }
}
```

### F6 — Security Groups

| SG                 | Inbound       | Source                                  |
| ------------------ | ------------- | --------------------------------------- |
| **Bastion**        | TCP 22 (SSH)  | IP admin saja — **hindari `0.0.0.0/0`** |
| **Content Server** | TCP 22 (SSH)  | SG Bastion                              |
| **Content Server** | TCP 80 (HTTP) | SG Target Servers                       |
| **Target Servers** | TCP 22 (SSH)  | SG Bastion + SG Content Server          |

### F7 — Secrets Management (SSM Parameter Store)

```bash
# Jalankan sekali dari mesin lokal sebelum terraform apply
aws ssm put-parameter \
  --name "/lab/rclone_token" \
  --value "<token_rclone>" \
  --type SecureString

aws ssm put-parameter \
  --name "/lab/bucket_name" \
  --value "lab-ansible-<suffix>" \
  --type String

aws ssm put-parameter \
  --name "/lab/ssh_public_key" \
  --value "$(cat ~/.ssh/lab_key.pub)" \
  --type String
```

> **Alasan:** User Data EC2 dapat dibaca via `ec2:DescribeInstances` — token yang di-inject langsung tersimpan sebagai plaintext.

### F8 — Validasi AMI Pre-flight (Terraform 1.2+)

```hcl
data "aws_ami" "rhel" {
  most_recent = true
  owners      = ["309956199498"]
  filter {
    name   = "name"
    values = ["RHEL-9.7*"]
  }
}

resource "aws_instance" "content_server" {
  ami = data.aws_ami.rhel.id
  # ...
  lifecycle {
    precondition {
      condition     = data.aws_ami.rhel.id != ""
      error_message = "RHEL 9.7 AMI tidak ditemukan di region ini. Verifikasi filter AMI."
    }
  }
}
```

---

## 4. Alur Eksekusi (Flag-Driven Pipeline)

### Fase 1 — Bastion Host: Upload ke S3

> **Catatan penting:** rclone melakukan transfer langsung GDrive → S3 tanpa menyimpan file di disk lokal Bastion. Karena itu, checksum **tidak bisa** diambil dari file lokal. Solusinya: download ISO dari S3 ke `/tmp` sementara hanya untuk hashing, lalu hapus setelah checksum di-upload.

```bash
#!/bin/bash
set -euo pipefail

# SSH hardening (jalankan sekali saat boot)
echo "PermitRootLogin no" >> /etc/ssh/sshd_config
echo "PasswordAuthentication no" >> /etc/ssh/sshd_config
systemctl restart sshd

# Ambil secrets dari SSM
BUCKET=$(aws ssm get-parameter \
  --name "/lab/bucket_name" \
  --query 'Parameter.Value' --output text)

RCLONE_TOKEN=$(aws ssm get-parameter \
  --name "/lab/rclone_token" \
  --with-decryption \
  --query 'Parameter.Value' --output text)

# Konfigurasi rclone dari SSM token
mkdir -p ~/.config/rclone
cat > ~/.config/rclone/rclone.conf <<EOF
[gdrive]
type = drive
token = ${RCLONE_TOKEN}
EOF

# Upload ISO: GDrive → S3 langsung (tidak ada file lokal)
rclone copy "gdrive:rhel/rhel-9.7-x86_64-dvd.iso" \
  "s3://${BUCKET}/iso/" \
  --progress \
  --s3-upload-concurrency 4

if [ $? -ne 0 ]; then
  echo "ERROR: rclone upload gagal." >&2
  exit 1
fi

# Generate checksum: download sementara ke /tmp hanya untuk hashing
# (ISO tidak tersimpan lokal saat rclone GDrive→S3, jadi harus diunduh ulang sesaat)
echo "Mengunduh ISO sementara ke /tmp untuk hashing..."
aws s3 cp "s3://${BUCKET}/iso/rhel-9.7-x86_64-dvd.iso" \
  /tmp/rhel-check.iso --no-progress

SHA_SUM=$(sha256sum /tmp/rhel-check.iso | awk '{print $1}')
echo "${SHA_SUM}" > /tmp/rhel.sha256

# Upload checksum ke S3
aws s3 cp /tmp/rhel.sha256 \
  "s3://${BUCKET}/iso/rhel-9.7-x86_64-dvd.iso.sha256"

# Cleanup file temp
rm -f /tmp/rhel-check.iso /tmp/rhel.sha256

# Set flag setelah semua berhasil
aws s3 cp /dev/null "s3://${BUCKET}/status/UPLOAD_DONE.flag"
echo "Upload & checksum selesai. Flag UPLOAD_DONE.flag di-set."
```

---

### Fase 2 — Content Server: Format, Download & Mount

#### Langkah 1: Time Sync & Dynamic Disk Discovery (Idempoten)

```bash
#!/bin/bash
set -euo pipefail

# Sinkronisasi waktu — wajib untuk Ansible dan token validation
systemctl enable --now chronyd
chronyc makestep

# Dynamic disk discovery — JANGAN hardcode /dev/nvme1n1
DATA_DISK=$(lsblk -d -n -o NAME,SIZE | grep '20G' | awk '{print $1}')

if [ -z "$DATA_DISK" ]; then
  echo "ERROR: Data disk 20GB tidak ditemukan!" >&2
  exit 1
fi

echo "Data disk terdeteksi: /dev/${DATA_DISK}"

# Idempoten: format hanya jika belum ada filesystem
if ! blkid "/dev/${DATA_DISK}" 2>/dev/null | grep -q 'xfs'; then
  mkfs.xfs -f "/dev/${DATA_DISK}"
  echo "Disk diformat sebagai XFS."
else
  echo "Filesystem XFS sudah ada — skip mkfs."
fi

mkdir -p /mnt/iso_data

if ! grep -q '/mnt/iso_data' /etc/fstab; then
  echo "/dev/${DATA_DISK} /mnt/iso_data xfs defaults,noatime 0 0" >> /etc/fstab
fi

mount -a
echo "Disk /dev/${DATA_DISK} terpasang di /mnt/iso_data."
```

#### Langkah 2: Polling S3 Flag (Timeout 30 Menit)

```bash
BUCKET=$(aws ssm get-parameter \
  --name "/lab/bucket_name" \
  --query 'Parameter.Value' --output text)

TIMEOUT=1800
ELAPSED=0
INTERVAL=30

echo "Menunggu UPLOAD_DONE.flag dari Bastion..."

while ! aws s3 ls "s3://${BUCKET}/status/UPLOAD_DONE.flag" &>/dev/null; do
  if [ $ELAPSED -ge $TIMEOUT ]; then
    echo "ERROR: Timeout ${TIMEOUT}s. Bastion mungkin gagal." >&2
    exit 1
  fi
  echo "Flag belum ada. Menunggu ${INTERVAL}s... (${ELAPSED}/${TIMEOUT}s)"
  sleep $INTERVAL
  ELAPSED=$((ELAPSED + INTERVAL))
done

echo "Flag terdeteksi. Memulai download ISO..."
```

#### Langkah 3: Download ISO + Validasi SHA256

```bash
aws s3 cp "s3://${BUCKET}/iso/rhel-9.7-x86_64-dvd.iso" \
  /mnt/iso_data/rhel-9.7-x86_64-dvd.iso \
  --no-progress

# Validasi integritas
EXPECTED_SUM=$(aws s3 cp "s3://${BUCKET}/iso/rhel-9.7-x86_64-dvd.iso.sha256" -)
ACTUAL_SUM=$(sha256sum /mnt/iso_data/rhel-9.7-x86_64-dvd.iso | awk '{print $1}')

if [ "$EXPECTED_SUM" != "$ACTUAL_SUM" ]; then
  echo "ERROR: SHA256 mismatch! ISO korup atau tidak lengkap." >&2
  exit 1
fi

echo "Integritas ISO terverifikasi (SHA256 cocok)."
```

#### Langkah 4: Mount ISO via systemd Mount Unit

> **⚠ Jangan gunakan `/etc/fstab` untuk loop mount ISO.** File source (`/mnt/iso_data/...`) mungkin belum tersedia saat fstab diproses di awal boot, menyebabkan **boot hang**. Gunakan systemd mount unit yang memiliki dependency ordering eksplisit.
>
> **⚠ Perhatikan escaping tanda hubung.** Nama unit systemd untuk path `/mnt/iso_data` harus menggunakan `mnt\-iso_data` (backslash sebelum tanda hubung) sesuai aturan systemd unit naming.

```bash
cat > /etc/systemd/system/var-www-html-rhel9.mount <<'EOF'
[Unit]
Description=Mount RHEL9 ISO for Local Repository
After=network.target local-fs.target mnt\-iso_data.mount
Requires=mnt\-iso_data.mount

[Mount]
What=/mnt/iso_data/rhel-9.7-x86_64-dvd.iso
Where=/var/www/html/rhel9
Type=iso9660
Options=loop,ro

[Install]
WantedBy=multi-user.target
EOF

mkdir -p /var/www/html/rhel9
systemctl daemon-reload
systemctl enable --now var-www-html-rhel9.mount

echo "ISO ter-mount via systemd unit."
```

#### Langkah 5: SELinux, Repo Lokal & HTTPD

```bash
# SELinux wajib dikonfigurasi — JANGAN setenforce 0
restorecon -Rv /var/www/html/rhel9
# Alternatif: setsebool -P httpd_read_user_content 1

# Repo untuk Content Server sendiri (file://)
cat > /etc/yum.repos.d/rhel9-local.repo <<EOF
[BaseOS-local]
name=RHEL 9 BaseOS (Local ISO)
baseurl=file:///var/www/html/rhel9/BaseOS
enabled=1
gpgcheck=0

[AppStream-local]
name=RHEL 9 AppStream (Local ISO)
baseurl=file:///var/www/html/rhel9/AppStream
enabled=1
gpgcheck=0
EOF

dnf install -y httpd ansible-core

# Install koleksi amazon.aws untuk Ansible SSM lookup
ansible-galaxy collection install amazon.aws

firewall-cmd --permanent --add-service=http
firewall-cmd --reload
systemctl enable --now httpd

echo "HTTPD aktif. Repo siap melayani target servers."
```

#### Langkah 6: SSH Key & Logrotate

```bash
# Ambil SSH public key dari SSM
mkdir -p ~/.ssh && chmod 700 ~/.ssh
aws ssm get-parameter \
  --name "/lab/ssh_public_key" \
  --query 'Parameter.Value' --output text \
  >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys

# Logrotate — cegah disk 30GB penuh oleh log selama lab
cat > /etc/logrotate.d/lab-logs <<EOF
/var/log/httpd/*log /var/log/ansible/*.log {
    daily
    rotate 3
    compress
    missingok
    notifempty
}
EOF

echo "SSH key & logrotate dikonfigurasi."
```

---

### Fase 3 — Target Servers: Repo, Hostname & Hosts Fallback

```bash
#!/bin/bash
set -euo pipefail

# Sinkronisasi waktu
systemctl enable --now chronyd
chronyc makestep

# NODE_HOSTNAME di-inject via Terraform templatefile()
NODE_NAME="${NODE_HOSTNAME}"

hostnamectl set-hostname "${NODE_NAME}.lab.fajjjar.my.id"

# /etc/hosts fallback — resolusi sebelum DNS Route53 propagasi sempurna
CONTENT_IP="172.25.250.254"
if ! grep -q "content.lab.fajjjar.my.id" /etc/hosts; then
  echo "${CONTENT_IP} content.lab.fajjjar.my.id content" >> /etc/hosts
fi

# SSH hardening
echo "PermitRootLogin no" >> /etc/ssh/sshd_config
echo "PasswordAuthentication no" >> /etc/ssh/sshd_config
systemctl restart sshd

# Hapus repo bawaan RHEL
rm -f /etc/yum.repos.d/redhat*.repo

# Arahkan ke Content Server via HTTP
cat > /etc/yum.repos.d/rhel9-content.repo <<EOF
[BaseOS]
name=RHEL 9 BaseOS
baseurl=http://content.lab.fajjjar.my.id/rhel9/BaseOS
enabled=1
gpgcheck=0

[AppStream]
name=RHEL 9 AppStream
baseurl=http://content.lab.fajjjar.my.id/rhel9/AppStream
enabled=1
gpgcheck=0
EOF

dnf clean all
dnf repolist
echo "Konfigurasi selesai pada ${NODE_NAME}."
```

---

## 5. Ansible Inventory & Verifikasi

File inventory di-push ke `/etc/ansible/inventory/hosts.ini` oleh Terraform (lihat F5).

```bash
# Verifikasi dari Content Server
ansible all -i /etc/ansible/inventory/hosts.ini -m ping
```

Distribusi SSH key ke managed nodes:

```yaml
# playbooks/distribute-ssh-key.yml
- name: Distribute SSH key to managed nodes
  hosts: managed
  become: true
  tasks:
    - name: Install amazon.aws collection jika belum ada
      ansible.builtin.command:
        cmd: ansible-galaxy collection install amazon.aws
      delegate_to: localhost
      run_once: true

    - name: Set authorized key dari SSM
      ansible.posix.authorized_key:
        user: ec2-user
        key: "{{ lookup('amazon.aws.ssm_parameter', '/lab/ssh_public_key', on_missing='warn') }}"
        state: present
```

> **Catatan:** Gunakan `lookup('amazon.aws.ssm_parameter', ...)` — bukan `lookup('amazon.aws.aws_ssm', ...)`. Koleksi `amazon.aws` wajib terinstall di Content Server (sudah ditangani di Fase 2 Langkah 5).

---

## 6. Keamanan & Akses

| Aspek                | Implementasi                                                                         |
| -------------------- | ------------------------------------------------------------------------------------ |
| **Secrets**          | Semua via SSM Parameter Store `SecureString` — tidak ada yang di-inject ke User Data |
| **SSH Hardening**    | `PermitRootLogin no`, `PasswordAuthentication no` di semua node                      |
| **IAM**              | Least Privilege dengan struktur JSON lengkap `Version` + `Statement` (lihat F3)      |
| **Security Groups**  | Lihat F6 — tidak ada `0.0.0.0/0` kecuali SSH Bastion dari IP admin                   |
| **S3 Bucket Policy** | Akses via VPC Gateway Endpoint, dibatasi ke bucket spesifik                          |
| **SELinux**          | Mode Enforcing dipertahankan — `restorecon`, bukan `setenforce 0`                    |
| **Time Sync**        | `chronyd` aktif di semua node — wajib untuk Ansible dan token validation             |
| **Log Rotation**     | `logrotate` dikonfigurasi di Content Server, retensi 3 hari                          |

---

## 7. Pertimbangan Biaya

### NAT Gateway vs NAT Instance

| Opsi                          | Estimasi Biaya       | Trade-off                                     |
| ----------------------------- | -------------------- | --------------------------------------------- |
| **NAT Gateway**               | ~$32/bulan + traffic | Fully managed, HA — cocok untuk production    |
| **NAT Instance** (`t3.nano`)  | ~$3–5/bulan          | Konfigurasi manual, cukup untuk lab sementara |
| **SSH ProxyJump** (tanpa NAT) | $0                   | Hanya SSH — target tidak bisa akses internet  |

Rekomendasi untuk lab RHCE: **NAT Instance**.

```hcl
resource "aws_instance" "nat" {
  ami                    = data.aws_ami.nat.id
  instance_type          = "t3.nano"
  subnet_id              = aws_subnet.public.id
  source_dest_check      = false   # Wajib untuk NAT
  vpc_security_group_ids = [aws_security_group.nat.id]
  tags = { Name = "lab-nat-instance" }
}

resource "aws_route" "private_nat" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = aws_instance.nat.primary_network_interface_id
}
```

---

## 8. Cleanup & Teardown

```bash
#!/bin/bash
# Jalankan setelah lab selesai untuk menghindari biaya berjalan terus

BUCKET=$(aws ssm get-parameter --name "/lab/bucket_name" \
  --query 'Parameter.Value' --output text)

# 1. Kosongkan S3 bucket (wajib sebelum terraform destroy)
aws s3 rm "s3://${BUCKET}" --recursive

# 2. Hapus parameter SSM
aws ssm delete-parameter --name "/lab/rclone_token"
aws ssm delete-parameter --name "/lab/bucket_name"
aws ssm delete-parameter --name "/lab/ssh_public_key"

# 3. Destroy semua resource Terraform
terraform destroy -auto-approve

echo "Cleanup selesai. Tidak ada resource aktif."
```

---

## 9. Kriteria Keberhasilan

| #   | Kriteria                                             | Cara Verifikasi                                 |
| --- | ---------------------------------------------------- | ----------------------------------------------- |
| 1   | Tidak ada disk full — root OS dan data disk terpisah | `df -h` pada Content Server                     |
| 2   | Integritas ISO via SHA256                            | SHA256 cocok antara S3 dan file lokal           |
| 3   | ISO ter-mount persisten via systemd unit             | `systemctl status var-www-html-rhel9.mount`     |
| 4   | Repo HTTP aktif — target bisa install paket          | `dnf install vim -y` dari salah satu target     |
| 5   | Ansible ping sukses ke 4 node                        | `ansible all -m ping`                           |
| 6   | Inventory otomatis tersedia post `terraform apply`   | `cat /etc/ansible/inventory/hosts.ini`          |
| 7   | Timeout flag berfungsi                               | Simulasi: hapus flag di S3, tunggu 30 menit     |
| 8   | SELinux tetap Enforcing                              | `getenforce` → `Enforcing`                      |
| 9   | Time sync aktif                                      | `chronyc tracking` menampilkan sumber NTP       |
| 10  | SSH hardening aktif                                  | `sshd -T \| grep -E 'permitroot\|passwordauth'` |

---

## 10. Checklist Final Go/No-Go Sebelum `terraform apply`

- [ ] AMI ID `RHEL-9.7.0_HVM-*` tersedia di region target (verifikasi via `aws ec2 describe-images`)
- [ ] Kepemilikan domain `fajjjar.my.id` dikonfirmasi untuk Route53 delegation
- [ ] Token rclone di SSM sebagai `SecureString`
- [ ] SSH public key di SSM sebagai `String`
- [ ] File SHA256 checksum ISO tersedia di sumber untuk diupload Bastion
- [ ] Terraform AWS Provider ≥ v5.0
- [ ] Terraform versi ≥ 1.2 (untuk `precondition` block di F8)
- [ ] `random_id` resource digunakan untuk nama bucket
- [ ] Route53 Private Hosted Zone diasosiasikan eksplisit ke VPC ID
- [ ] vCPU quota `t3.large` dan `t3.medium` dicek di akun AWS target
- [ ] Security Group Bastion dibatasi ke IP admin
- [ ] Provisioner `null_resource` memiliki SSHD wait logic (F5)
- [ ] Koleksi `amazon.aws` diinstall di Content Server (Fase 2 Langkah 5)
- [ ] Script teardown (Bagian 8) disiapkan sebelum lab dimulai
