terraform {
  required_version = ">= 1.2"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "lab-ansible"
      ManagedBy = "terraform"
    }
  }
}

# ──────────────────────────────────────────────
# Data Sources
# ──────────────────────────────────────────────

# RHEL 9.7 AMI — TODO: UPDATE_ON_RELEASE
data "aws_ami" "rhel" {
  most_recent = true
  owners      = ["309956199498"]

  filter {
    name   = "name"
    values = ["RHEL-9.7*_HVM-*-x86_64-*-Hourly2-GP3"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

# Amazon Linux 2023 for NAT Instance
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# Auto-detect admin public IP for security group
data "http" "my_ip" {
  url = "https://checkip.amazonaws.com"
}

data "aws_availability_zones" "available" {
  state = "available"
}

# ──────────────────────────────────────────────
# SSH Key Pair (from ~/.ssh/id_ed25519.pub)
# ──────────────────────────────────────────────
resource "aws_key_pair" "lab" {
  key_name   = "lab-ansible-key"
  public_key = file(var.ssh_public_key_path)
  tags       = { Name = "lab-ansible-key" }
}
