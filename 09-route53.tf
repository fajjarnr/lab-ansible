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
  records = [aws_instance.content_server.private_ip]
}

# Target Servers
resource "aws_route53_record" "target" {
  for_each = toset(local.target_names)

  zone_id = aws_route53_zone.lab.zone_id
  name    = "${each.key}.${var.domain}"
  type    = "A"
  ttl     = 300
  records = [aws_instance.target[each.key].private_ip]
}
