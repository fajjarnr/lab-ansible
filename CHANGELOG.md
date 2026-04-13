# Changelog

All notable changes to this project are documented in this file.

## [1.1.0] - 2026-04-13

### Fixed

- `10-outputs.tf`: output `content_server_ssh_via_bastion` was hardcoded to `172.25.250.254` — now uses `aws_instance.content_server.private_ip` (dynamic)
- `07-content-server.tf`: Ansible inventory `[managed]` block had inconsistent leading whitespace due to `%{for~}` heredoc — replaced with `join("\n", [...])` for clean output
- `scripts/day2-automation.sh`: Added `sudo` to bastion and content server `cloud-init status --wait` (PermissionError on `cloud-init` 24.4 without root)
- `scripts/day2-automation.sh`: Systemd mount unit for ISO now declares `After=mnt-iso_data.mount` and `Requires=mnt-iso_data.mount` dependency — prevents mount failure on reboot
- `scripts/day2-automation.sh`: ISO mount option now includes SELinux context (`context=system_u:object_r:httpd_sys_content_t:s0`) — fixes potential httpd 403 under SELinux enforcing
- `scripts/upload_iso.sh`: Removed hardcoded bucket name `lab-ansible-42813f` — now accepts bucket as `$1` argument

## [1.0.0] - 2026-04-10

### Added

#### Infrastructure (Terraform)

- AWS VPC (`172.25.0.0/16`) with public and private subnets
- Internet Gateway + route tables for public/private subnet isolation
- S3 VPC Gateway Endpoint with split policy (global reads for OS repos, restricted writes)
- Bastion host (`t3.large`, RHEL 9.7) with Elastic IP and SSH hardening
- NAT instance (`t3.nano`, Amazon Linux 2023) with iptables masquerade
- Content server (`t3.large`, RHEL 9.7) with 20GB EBS data disk
- 4 target servers (`t3.medium`, RHEL 9.7) via `for_each`
- S3 bucket with random suffix for ISO storage
- IAM roles with least-privilege policies (bastion: S3 read/write, content: S3 read)
- Route53 private hosted zone (`lab.fajjjar.my.id`) with A records for all servers
- Security groups: bastion (SSH from admin IP), NAT, content server, target servers
- Auto-generated Ansible inventory (`inventory/hosts.ini`)

#### Automation

- Day-2 orchestration via `null_resource` + `local-exec`
- Phase 1: Idempotent ISO upload (GDrive → S3 via rclone on bastion)
- Phase 2: Idempotent content server setup (S3 → EBS, SHA256 verify, systemd mount)
- User data scripts for all instance types (NAT, bastion, content, targets)

#### Ansible

- Playbook `setup-local-repo.yml`: configures local BaseOS + AppStream repos on all targets
- Disables RHUI repos, validates with `dnf repolist`, test-installs `tree` package

#### Documentation

- `README.md` with architecture diagram, quick start, project structure, cost estimate
- `ARCHITECTURE.md` with network design, security groups, automation flow
- `GEMINI.md` with AI pair-programming session notes
- `PRD.md` (Product Requirements Document v9.0)

### Fixed (initial release)

- S3 VPC Endpoint policy blocking OS package mirrors (AL2023 `dnf install` failures)
- NAT instance `iptables` package name (`iptables` vs deprecated `iptables-nft-services`)
- Systemd mount unit heredoc variable expansion (hardcoded paths)
- Missing `unzip` dependency on content server for AWS CLI installation
- rclone S3 region constraint and `--s3-no-check-bucket` flags
