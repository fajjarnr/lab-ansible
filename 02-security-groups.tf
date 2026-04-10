# ──────────────────────────────────────────────
# Admin IP detection
# ──────────────────────────────────────────────
locals {
  admin_cidr = "${trimspace(data.http.my_ip.response_body)}/32"
}

# ──────────────────────────────────────────────
# Bastion SG — SSH from admin IP only
# ──────────────────────────────────────────────
resource "aws_security_group" "bastion" {
  name_prefix = "lab-bastion-"
  description = "Bastion - SSH from admin IP only"
  vpc_id      = aws_vpc.lab.id

  ingress {
    description = "SSH from admin IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [local.admin_cidr]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "lab-bastion-sg" }

  lifecycle { create_before_destroy = true }
}

# ──────────────────────────────────────────────
# NAT SG — all traffic from private subnet
# ──────────────────────────────────────────────
resource "aws_security_group" "nat" {
  name_prefix = "lab-nat-"
  description = "NAT instance - traffic from private subnet"
  vpc_id      = aws_vpc.lab.id

  ingress {
    description = "All from private subnet"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.private_subnet_cidr]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "lab-nat-sg" }

  lifecycle { create_before_destroy = true }
}

# ──────────────────────────────────────────────
# Content Server SG — SSH from bastion, HTTP from targets
# ──────────────────────────────────────────────
resource "aws_security_group" "content_server" {
  name_prefix = "lab-content-"
  description = "Content server - SSH from bastion, HTTP from targets"
  vpc_id      = aws_vpc.lab.id

  ingress {
    description     = "SSH from bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "lab-content-sg" }

  lifecycle { create_before_destroy = true }
}

# ──────────────────────────────────────────────
# Target Servers SG — SSH from bastion + content server
# ──────────────────────────────────────────────
resource "aws_security_group" "target_servers" {
  name_prefix = "lab-target-"
  description = "Target servers - SSH from bastion + content server"
  vpc_id      = aws_vpc.lab.id

  ingress {
    description = "SSH from bastion and content server"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    security_groups = [
      aws_security_group.bastion.id,
      aws_security_group.content_server.id
    ]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "lab-target-sg" }

  lifecycle { create_before_destroy = true }
}

# ──────────────────────────────────────────────
# Cross-SG rule: Content Server HTTP ← Target Servers
# ──────────────────────────────────────────────
resource "aws_security_group_rule" "content_http_from_targets" {
  type                     = "ingress"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.target_servers.id
  security_group_id        = aws_security_group.content_server.id
  description              = "HTTP from target servers for yum repo"
}
resource "aws_security_group_rule" "nat_from_bastion" {
  type                     = "ingress"
  from_port                = 22
  to_port                  = 22
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.bastion.id
  security_group_id        = aws_security_group.nat.id
  description              = "SSH from Bastion"
}

