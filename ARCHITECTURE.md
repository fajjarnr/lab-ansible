# Architecture

## Overview

This lab implements a **multi-tier enterprise network topology** on AWS, isolating managed infrastructure behind a private subnet while exposing only the bastion host to the internet.

## Network Design

### VPC: `172.25.0.0/16`

| Subnet  | CIDR              | Type    | Purpose                         |
| ------- | ----------------- | ------- | ------------------------------- |
| Public  | `172.25.254.0/24` | Public  | Bastion + NAT instance          |
| Private | `172.25.250.0/24` | Private | Content server + target servers |

### Routing

```
Internet ◄──► IGW ◄──► Public Subnet (Bastion, NAT)
                              │
                         NAT Instance (iptables MASQUERADE)
                              │
                        Private Subnet (Content, Targets)
                              │
                         S3 VPC Gateway Endpoint (no internet needed for S3)
```

- **Public subnet** has a direct route to IGW (`0.0.0.0/0 → igw`)
- **Private subnet** routes through NAT instance (`0.0.0.0/0 → NAT ENI`)
- **S3 traffic** bypasses NAT entirely via VPC Gateway Endpoint

## Compute

### Bastion Host (`lab-bastion`)

- **Role:** SSH gateway, ISO upload executor
- **Type:** `t3.large` / RHEL 9.7
- **Network:** Public subnet with Elastic IP
- **IAM:** S3 read/write (iso/_, status/_) + SSM read
- **Software:** AWS CLI v2, rclone (GDrive transfer)

### NAT Instance (`lab-nat-instance`)

- **Role:** Internet gateway for private subnet (cost-effective alternative to NAT Gateway)
- **Type:** `t3.nano` / Amazon Linux 2023
- **Network:** Public subnet, `source_dest_check = false`
- **Config:** `iptables -t nat -j MASQUERADE`, `ip_forward = 1`

### Content Server (`lab-content-server`)

- **Role:** Ansible control node + local RHEL repository via HTTP
- **Type:** `t3.large` / RHEL 9.7
- **Network:** Private subnet, dynamic IP (assigned by DHCP from `172.25.250.0/24`)
- **Storage:** 30GB root + 20GB EBS data disk (`/mnt/iso_data`)
- **IAM:** S3 read (download ISO) + SSM read
- **Software:** ansible-core, httpd, AWS CLI v2
- **Mount:** RHEL ISO → `/var/www/html/rhel9` via systemd mount unit (SELinux context set)

### Target Servers (`lab-servera` through `lab-serverd`)

- **Role:** Ansible managed nodes
- **Type:** `t3.medium` / RHEL 9.7
- **Network:** Private subnet, dynamic IPs (assigned by DHCP from `172.25.250.0/24`)
- **Repos:** Configured to use content server's local HTTP repo via DNS (`content.lab.fajjjar.my.id`)

## Security Groups

```
┌─────────────────────────────────────────┐
│ Bastion SG                              │
│  IN:  SSH (22) from admin IP            │
│  OUT: All                               │
├─────────────────────────────────────────┤
│ NAT SG                                  │
│  IN:  All from 172.25.250.0/24          │
│  IN:  SSH (22) from Bastion SG          │
│  OUT: All                               │
├─────────────────────────────────────────┤
│ Content Server SG                       │
│  IN:  SSH (22) from Bastion SG          │
│  IN:  HTTP (80) from Target SG          │
│  OUT: All                               │
├─────────────────────────────────────────┤
│ Target Servers SG                       │
│  IN:  SSH (22) from Bastion + Content   │
│  OUT: All                               │
└─────────────────────────────────────────┘
```

## S3 & VPC Endpoint

- **Bucket:** `lab-ansible-XXXXXX` (random suffix)
- **VPC Endpoint:** Gateway type for S3
  - `s3:GetObject` allowed globally (OS package mirrors live on S3)
  - `s3:PutObject`, `s3:ListBucket` restricted to lab bucket only
- **Public access:** Fully blocked

## DNS (Route53)

Private hosted zone: `lab.fajjjar.my.id`

| Record                      | IP                                  |
| --------------------------- | ----------------------------------- |
| `bastion.lab.fajjjar.my.id` | Bastion private IP (dynamic)        |
| `content.lab.fajjjar.my.id` | Content server private IP (dynamic) |
| `servera.lab.fajjjar.my.id` | servera private IP (dynamic)        |
| `serverb.lab.fajjjar.my.id` | serverb private IP (dynamic)        |
| `serverc.lab.fajjjar.my.id` | serverc private IP (dynamic)        |
| `serverd.lab.fajjjar.my.id` | serverd private IP (dynamic)        |

## Day-2 Automation Flow

```
terraform apply
       │
       ├─ 1. Provision all AWS resources (45+)
       │
       └─ 2. null_resource.day2_orchestration (local-exec)
              │
              ├─ Phase 1: ISO Upload (idempotent)
              │    ├─ Check UPLOAD_DONE.flag in S3
              │    ├─ If missing: scp rclone.conf → bastion
              │    ├─ rclone copy gdrive:rhel/*.iso → s3://bucket/iso/
              │    ├─ Generate SHA256 checksum
              │    └─ Create UPLOAD_DONE.flag
              │
              └─ Phase 2: Content Server Setup (idempotent)
                   ├─ Check if ISO already mounted
                   ├─ If not: install AWS CLI + unzip
                   ├─ aws s3 cp ISO → /mnt/iso_data/
                   ├─ Verify SHA256 checksum
                   ├─ Create systemd mount unit
                   └─ Mount ISO → /var/www/html/rhel9
```

## Design Decisions

| Decision                    | Rationale                                                                        |
| --------------------------- | -------------------------------------------------------------------------------- |
| NAT Instance vs NAT Gateway | Cost: ~$3.50/mo vs ~$32/mo. Acceptable for lab.                                  |
| S3 VPC Endpoint             | Allows private subnet to access S3 without NAT. Required for OS mirrors.         |
| Separate EBS volume         | Content server data disk is independent of root — survives instance replacement. |
| `for_each` for targets      | DRY: 4 servers from 1 resource block. Easy to add/remove.                        |
| Static private IPs          | Predictable addressing for `/etc/hosts` and Ansible inventory.                   |
| ed25519 SSH key             | Modern, faster, smaller keys than RSA. User's existing key.                      |
| Idempotent automation       | Safe to re-run `terraform apply` — skips completed phases.                       |
