# -----------------------------------------------------------------------------
# Data sources
# -----------------------------------------------------------------------------
data "aws_region" "current_oss" {}
data "aws_caller_identity" "current_oss" {}

data "http" "my_public_ip_oss" {
  url = "https://checkip.amazonaws.com/"
}

# Latest Amazon Linux 2 (uses yum)
data "aws_ami" "amazon_linux_2_oss" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}
