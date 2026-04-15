provider "aws" {
  region = "us-west-2"
}

# Publicly Accessible S3 Bucket with No Encryption (HIGH)
resource "aws_s3_bucket" "insecure_bucket" {
  bucket = "my-insecure-bucket-12345"
  acl    = "public-read-write"
}

# Security Group Allowing All Traffic (CRITICAL)
resource "aws_security_group" "open_all" {
  name = "open-all-sg"

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# EC2 Instance with Hardcoded Key Pair (MEDIUM)
resource "aws_instance" "insecure_ec2" {
  ami           = "ami-0abcdef1234567890"
  instance_type = "t2.micro"

  key_name = "my-keypair"

  associate_public_ip_address = true
}

# RDS Database Publicly Accessible (CRITICAL)
resource "aws_db_instance" "public_db" {
  allocated_storage    = 20
  engine               = "postgres"
  instance_class       = "db.t3.micro"
  username             = "root"
  password             = "root123"
  publicly_accessible  = true
  skip_final_snapshot  = true
  storage_encrypted    = false
}

# Unrestricted Network ACL (HIGH)
resource "aws_network_acl" "open_acl" {
  vpc_id = "vpc-12345678"

  ingress {
    rule_no    = 100
    protocol   = "-1"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  egress {
    rule_no    = 100
    protocol   = "-1"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }
}

# Unencrypted EBS Snapshot (MEDIUM)
resource "aws_ebs_snapshot" "unencrypted_snapshot" {
  volume_id = "vol-12345678"
}

# IAM Role with Full Access (CRITICAL)
resource "aws_iam_role_policy" "full_access" {
  name = "full-access-policy"
  role = "example-role"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "*"
      Resource = "*"
    }]
  })
}
