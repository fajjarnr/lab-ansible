# ──────────────────────────────────────────────
# Route53 Private Hosted Zone
# ──────────────────────────────────────────────
resource "aws_route53_zone" "lab" {
  name = var.domain

  vpc {
    vpc_id = aws_vpc.lab.id
  }

  tags = { Name = "lab-ansible-dns" }
}

# ──────────────────────────────────────────────
# DNS Records
# ──────────────────────────────────────────────

# Bastion
resource "aws_route53_record" "bastion" {
  zone_id = aws_route53_zone.lab.zone_id
  name    = "bastion.${var.domain}"
  type    = "A"
  ttl     = 300
  records = [aws_instance.bastion.private_ip]
}

# Content Server
resource "aws_route53_record" "content" {
  zone_id = aws_route53_zone.lab.zone_id
  name    = "content.${var.domain}"
  type    = "A"
  ttl     = 300
  records = ["172.25.250.254"]
}

# Target Servers
resource "aws_route53_record" "target" {
  for_each = local.target_servers

  zone_id = aws_route53_zone.lab.zone_id
  name    = "${each.key}.${var.domain}"
  type    = "A"
  ttl     = 300
  records = [each.value.ip]
}
