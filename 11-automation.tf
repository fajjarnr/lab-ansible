# ──────────────────────────────────────────────
# Day 2 Automation Workflow
# ──────────────────────────────────────────────

resource "null_resource" "day2_orchestration" {
  # This triggers on every apply but the bash script is structurally idempotent (safe to re-run).
  triggers = {
    always_run = timestamp()
  }

  depends_on = [
    aws_instance.bastion,
    aws_instance.content_server,
    aws_s3_bucket.lab,
    local_file.ansible_inventory
  ]

  provisioner "local-exec" {
    command     = "chmod +x ${path.module}/scripts/day2-automation.sh && ${path.module}/scripts/day2-automation.sh ${aws_eip.bastion.public_ip} ${aws_instance.content_server.private_ip} ${aws_s3_bucket.lab.bucket}"
    interpreter = ["/bin/bash", "-c"]
  }
}
