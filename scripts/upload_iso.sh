#!/bin/bash
set -euo pipefail

BUCKET="lab-ansible-42813f"

echo "1. Uploading ISO from GDrive to S3..."
rclone copy "gdrive:rhel/rhel-9.7-x86_64-dvd.iso" \
  "s3:${BUCKET}/iso/" \
  --s3-region ap-southeast-1 \
  --s3-location-constraint ap-southeast-1 \
  --s3-no-check-bucket \
  --progress \
  --s3-upload-concurrency 4
echo "Upload to S3 completed."

echo "2. Downloading ISO temporarily for checksum generation..."
aws s3 cp "s3://${BUCKET}/iso/rhel-9.7-x86_64-dvd.iso" /tmp/rhel-check.iso --no-progress

echo "3. Calculating SHA256..."
SHA_SUM=$(sha256sum /tmp/rhel-check.iso | awk '{print $1}')
echo "${SHA_SUM}" > /tmp/rhel.sha256
echo "SHA256: ${SHA_SUM}"

echo "4. Uploading checksum..."
aws s3 cp /tmp/rhel.sha256 "s3://${BUCKET}/iso/rhel-9.7-x86_64-dvd.iso.sha256"

echo "5. Cleaning up Temp files..."
rm -f /tmp/rhel-check.iso /tmp/rhel.sha256

echo "6. Creating UPLOAD_DONE.flag..."
aws s3 cp /dev/null "s3://${BUCKET}/status/UPLOAD_DONE.flag"

echo "DONE."
