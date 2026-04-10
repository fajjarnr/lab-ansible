# GEMINI.md — AI Pair-Programming Notes

This project was built through an AI pair-programming session using Gemini/Claude as the coding assistant. This document records key decisions, debugging sessions, and lessons learned.

## Session Overview

- **Date:** 2026-04-10
- **Duration:** ~2 hours
- **Scope:** Full infrastructure provisioning, Day-2 automation, and Ansible playbook execution
- **Result:** 45+ AWS resources deployed, ISO pipeline automated, Ansible verified on all 4 targets

## Key Debugging Episodes

### 1. NAT Instance — `iptables: command not found`

**Problem:** The NAT instance user data tried to install `iptables-nft-services` and `iptables-services`, but neither package exists on Amazon Linux 2023.

**Root Cause:** Amazon Linux 2023 ships iptables as the base `iptables` package (not `-services` or `-nft-services`). Additionally, AL2023 fetches packages from S3-hosted mirrors, which were blocked by the restrictive S3 VPC Endpoint policy.

**Fix:**
1. Changed package name to `dnf install -y iptables`
2. Split S3 VPC Endpoint policy: `s3:GetObject` allowed globally (for OS mirrors), writes restricted to lab bucket
3. Recreated NAT instance with `terraform apply -replace="aws_instance.nat"`

### 2. S3 VPC Endpoint — Blocking OS Package Downloads

**Problem:** All instances in the private subnet couldn't `dnf install` anything. Error: `Status code: 403` from AL2023/RHEL S3 mirrors.

**Root Cause:** The S3 VPC Endpoint policy only allowed access to `lab-ansible-*` bucket. But RHEL and AL2023 download packages from AWS-hosted S3 buckets (e.g., `al2023-repos-ap-southeast-1-*.s3.amazonaws.com`).

**Fix:** Added a separate statement allowing `s3:GetObject` on `arn:aws:s3:::*` (read-only, global) while keeping write operations restricted.

### 3. rclone — S3 Region and Bucket Check Errors

**Problem:** rclone copy from GDrive to S3 failed with `IllegalLocationConstraintException` and `CreateBucket: AccessDenied`.

**Root Cause:** rclone's S3 backend tries to create the bucket if it doesn't exist and uses the wrong region when not specified explicitly.

**Fix:** Added flags: `--s3-region ap-southeast-1 --s3-location-constraint ap-southeast-1 --s3-no-check-bucket`

### 4. Systemd Mount Unit — Variables Not Expanded

**Problem:** The `var-www-html-rhel9.mount` unit had literal `$ISO_PATH` and `$MOUNT_DIR` instead of actual paths.

**Root Cause:** The heredoc was single-quoted (`<< 'MOUNT'`), which prevents variable expansion. Since it was nested inside another heredoc (`<< 'EOF'`), the escaping was complex.

**Fix:** Hardcoded the paths directly in the mount unit definition.

### 5. Content Server — `aws: command not found`

**Problem:** The Day-2 automation script failed on the content server because AWS CLI wasn't installed.

**Root Cause:** The content server user data script was supposed to install AWS CLI, but it ran before the NAT instance was properly configured (chicken-and-egg: NAT needed iptables from S3, but S3 endpoint was too restrictive).

**Fix:** Added AWS CLI installation (with `unzip` dependency) directly in the Day-2 automation script, ensuring it runs after NAT is fully operational.

## Design Insights

1. **VPC Endpoint policies are tricky.** AWS services (including their own OS mirrors) rely on S3. A restrictive endpoint policy can break fundamental operations like `dnf install`.

2. **NAT Instance > NAT Gateway for labs.** $3.50/mo vs $32/mo. The trade-off is complexity (iptables config, instance management), but it's worth it for non-production use.

3. **Idempotent automation matters.** The Day-2 script checks for `UPLOAD_DONE.flag` and `mount | grep` before running. This makes `terraform apply` safe to re-run.

4. **Heredocs inside SSH commands are fragile.** Nested quoting and variable expansion across multiple shell layers is error-prone. Hardcoding values or using `scp` to transfer scripts is more reliable.

5. **User data scripts can fail silently.** Always check `/var/log/userdata.log` and `cloud-init-output.log`. Don't assume user data completed successfully.
