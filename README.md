# Automated Enterprise Ansible Lab

Automated multi-tier Ansible lab environment on AWS, provisioned entirely with Terraform. Designed for hands-on practice with Ansible in an enterprise-like topology — complete with a bastion host, NAT instance, content server (local RHEL repo), and four managed target nodes.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          VPC 172.25.0.0/16                                  │
│                                                                             │
│  ┌──────────── Public Subnet 172.25.254.0/24 ────────────┐                 │
│  │   ┌──────────────┐         ┌──────────────┐           │                 │
│  │   │   Bastion     │         │ NAT Instance │           │    IGW          │
│  │   │  t3.large     │         │  t3.nano     │           │◄──►Internet    │
│  │   │  RHEL 9.7     │         │  AL2023      │           │                 │
│  │   │  EIP attached │         │  iptables    │           │                 │
│  │   └──────────────┘         └──────┬───────┘           │                 │
│  └───────────────────────────────────┼───────────────────┘                 │
│                                      │                                      │
│  ┌──────────── Private Subnet 172.25.250.0/24 ───────────┐                 │
│  │                                   │                    │                 │
│  │   ┌──────────────────────────────┐│                    │                 │
│  │   │    Content Server            ││                    │                 │
│  │   │    172.25.250.254            ││                    │                 │
│  │   │    t3.large / RHEL 9.7       ││                    │                 │
│  │   │    httpd + Ansible Control   ││                    │                 │
│  │   │    20GB EBS (ISO storage)    ││                    │                 │
│  │   └──────────────────────────────┘│                    │                 │
│  │                                   │                    │                 │
│  │   ┌───────────┐ ┌───────────┐ ┌───────────┐ ┌────────┐│                 │
│  │   │ servera   │ │ serverb   │ │ serverc   │ │serverd ││                 │
│  │   │ .250.10   │ │ .250.11   │ │ .250.12   │ │.250.13 ││                 │
│  │   │ t3.medium │ │ t3.medium │ │ t3.medium │ │t3.med  ││                 │
│  │   └───────────┘ └───────────┘ └───────────┘ └────────┘│                 │
│  └────────────────────────────────────────────────────────┘                 │
│                                                                             │
│  S3 Endpoint (Gateway) ─── lab-ansible-XXXXXX bucket                       │
│  Route53 Private Zone ─── lab.fajjjar.my.id                                │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Quick Start

### Prerequisites

- Terraform >= 1.5
- AWS CLI v2 configured (`aws sts get-caller-identity`)
- SSH key at `~/.ssh/id_ed25519.pub`
- rclone configured with Google Drive remote (`~/.config/rclone/rclone.conf`)
- RHEL 9.7 ISO on Google Drive at `gdrive:rhel/rhel-9.7-x86_64-dvd.iso`

### Deploy

```bash
terraform init
terraform plan
terraform apply
```

The `terraform apply` will automatically:
1. Provision all 45+ AWS resources
2. Upload RHEL ISO from Google Drive → S3 (via bastion)
3. Download ISO to content server and mount as local HTTP repo
4. Generate Ansible inventory at `inventory/hosts.ini`

### SSH Access

```bash
# Bastion (direct)
ssh -i ~/.ssh/id_ed25519 ec2-user@<BASTION_EIP>

# Content Server (via bastion)
ssh -i ~/.ssh/id_ed25519 -J ec2-user@<BASTION_EIP> ec2-user@172.25.250.254

# Target Servers (via bastion)
ssh -i ~/.ssh/id_ed25519 -J ec2-user@<BASTION_EIP> ec2-user@172.25.250.10  # servera
ssh -i ~/.ssh/id_ed25519 -J ec2-user@<BASTION_EIP> ec2-user@172.25.250.11  # serverb
ssh -i ~/.ssh/id_ed25519 -J ec2-user@<BASTION_EIP> ec2-user@172.25.250.12  # serverc
ssh -i ~/.ssh/id_ed25519 -J ec2-user@<BASTION_EIP> ec2-user@172.25.250.13  # serverd
```

### Run Ansible

```bash
# SSH to content server, then:
ansible all -m ping
ansible-playbook ~/setup-local-repo.yml
```

## Project Structure

```
lab-ansible/
├── main.tf                         # Provider, AMI lookups, SSH key pair
├── variables.tf                    # Input variables
├── terraform.tfvars                # Variable values (region, CIDRs)
├── 01-network.tf                   # VPC, subnets, IGW, routes, S3 endpoint
├── 02-security-groups.tf           # Bastion, NAT, Content, Target SGs
├── 03-nat-instance.tf              # NAT instance + private route
├── 04-s3.tf                        # S3 bucket (ISO storage)
├── 05-iam.tf                       # IAM roles + instance profiles
├── 06-bastion.tf                   # Bastion host + Elastic IP
├── 07-content-server.tf            # Content server + EBS + inventory
├── 08-target-servers.tf            # 4 target servers (for_each)
├── 09-route53.tf                   # Private DNS zone + records
├── 10-outputs.tf                   # SSH commands, IPs, bucket name
├── 11-automation.tf                # Day-2 orchestration trigger
├── scripts/
│   ├── nat-userdata.sh.tpl         # NAT: IP forwarding + iptables
│   ├── bastion-userdata.sh.tpl     # Bastion: SSH hardening, AWS CLI
│   ├── content-server-userdata.sh.tpl  # Content: disk, httpd, ansible
│   ├── target-userdata.sh.tpl      # Target: hostname, chronyd
│   ├── day2-automation.sh          # Orchestrate ISO upload + mount
│   └── upload_iso.sh               # GDrive → S3 via rclone
├── playbooks/
│   └── setup-local-repo.yml       # Configure local yum repo on targets
├── PRD.md                          # Product Requirements Document
├── ARCHITECTURE.md                 # Architecture deep-dive
├── CHANGELOG.md                    # Version history
├── GEMINI.md                       # AI pair-programming notes
└── README.md                       # This file
```

## Cleanup

```bash
terraform destroy -auto-approve
```

## Cost Estimate

| Resource | Type | Est. Monthly Cost |
|----------|------|-------------------|
| Bastion | t3.large | ~$60 |
| Content Server | t3.large | ~$60 |
| NAT Instance | t3.nano | ~$3.50 |
| Target Servers (4x) | t3.medium | ~$120 |
| EBS Volumes | gp3 | ~$15 |
| S3 | Standard | ~$0.30 |
| Route53 | Private Zone | ~$0.50 |
| **Total** | | **~$260/mo** |

> **Tip:** Destroy the lab when not in use to avoid unnecessary costs.

## License

MIT
