provider "aws" {
  region = "us-east-1"
}

# ── 1. CRITICAL — S3 Bucket Fully Public ──────────────────────────────────────
resource "aws_s3_bucket" "public_bucket" {
  bucket = "vulnerable-public-bucket"
  acl    = "public-read-write"         # anyone can read AND write
}

resource "aws_s3_bucket_policy" "public_policy" {
  bucket = aws_s3_bucket.public_bucket.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = "*"                  # anyone in the world
      Action    = "s3:*"              # full access
      Resource  = "*"
    }]
  })
}

# ── 2. CRITICAL — Security Group Open to World ────────────────────────────────
resource "aws_security_group" "open_all" {
  name = "open-all-sg"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]       # SSH open to world
  }

  ingress {
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]       # RDP open to world
  }

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]       # ALL traffic open to world
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]       # all outbound allowed
  }
}

# ── 3. CRITICAL — RDS with Hardcoded Credentials + No Encryption ──────────────
resource "aws_db_instance" "insecure_db" {
  allocated_storage       = 20
  engine                  = "mysql"
  engine_version          = "5.7"
  instance_class          = "db.t3.micro"
  username                = "admin"
  password                = "password123"  # hardcoded password
  skip_final_snapshot     = true
  storage_encrypted       = false          # no encryption
  publicly_accessible     = true           # exposed to internet
  deletion_protection     = false
  backup_retention_period = 0              # no backups
  multi_az                = false
}

# ── 4. CRITICAL — IAM Full Admin Access ───────────────────────────────────────
resource "aws_iam_policy" "admin_policy" {
  name = "full-admin-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "*"                   # full admin
      Resource = "*"
    }]
  })
}

resource "aws_iam_user" "admin_user" {
  name = "admin-user"
}

resource "aws_iam_user_policy_attachment" "admin_attach" {
  user       = aws_iam_user.admin_user.name
  policy_arn = aws_iam_policy.admin_policy.arn
}

# ── 5. CRITICAL — Hardcoded AWS Credentials ───────────────────────────────────
provider "aws" {
  alias      = "hardcoded"
  region     = "us-east-1"
  access_key = "AKIAIOSFODNN7EXAMPLE"        # hardcoded access key
  secret_key = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"  # hardcoded secret
}

# ── 6. MEDIUM — EC2 with Public IP + No IMDSv2 ────────────────────────────────
resource "aws_instance" "public_ec2" {
  ami                         = "ami-0c02fb55956c7d316"
  instance_type               = "t2.micro"
  associate_public_ip_address = true         # public IP exposed
  vpc_security_group_ids      = [aws_security_group.open_all.id]

  metadata_options {
    http_tokens = "optional"                 # IMDSv1 allowed — insecure
  }

  user_data = <<-EOF
    #!/bin/bash
    echo "admin:password123" | chpasswd     # hardcoded credentials in userdata
    export AWS_SECRET_KEY="mysecretkey123"  # secret in userdata
  EOF
}

# ── 7. MEDIUM — Unencrypted EBS Volume ────────────────────────────────────────
resource "aws_ebs_volume" "unencrypted_volume" {
  availability_zone = "us-east-1a"
  size              = 10
  encrypted         = false                  # no encryption
}

# ── 8. HIGH — CloudTrail Logging Disabled ─────────────────────────────────────
resource "aws_cloudtrail" "insecure_trail" {
  name                          = "insecure-trail"
  s3_bucket_name                = aws_s3_bucket.public_bucket.id
  include_global_service_events = false      # global events not logged
  is_multi_region_trail         = false      # single region only
  enable_log_file_validation    = false      # no log validation
}

# ── 9. HIGH — KMS Key with No Rotation ────────────────────────────────────────
resource "aws_kms_key" "no_rotation" {
  description             = "KMS key without rotation"
  enable_key_rotation     = false            # key never rotates
  deletion_window_in_days = 7
}

# ── 10. HIGH — ElasticSearch Domain Publicly Accessible ───────────────────────
resource "aws_elasticsearch_domain" "public_es" {
  domain_name           = "vulnerable-es"
  elasticsearch_version = "7.10"

  access_policies = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = "*" }             # open to everyone
      Action    = "es:*"
      Resource  = "*"
    }]
  })

  encrypt_at_rest {
    enabled = false                          # no encryption at rest
  }

  node_to_node_encryption {
    enabled = false                          # no node encryption
  }
}

# ── 11. HIGH — Lambda with Full Admin Role ────────────────────────────────────
resource "aws_iam_role" "lambda_admin" {
  name = "lambda-admin-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "lambda_admin_policy" {
  role = aws_iam_role.lambda_admin.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "*"                        # full admin for lambda
      Resource = "*"
    }]
  })
}

# ── 12. MEDIUM — SQS Queue Not Encrypted ──────────────────────────────────────
resource "aws_sqs_queue" "unencrypted_queue" {
  name                    = "unencrypted-queue"
  kms_master_key_id       = ""             # no encryption key
}

# ── 13. MEDIUM — SNS Topic Not Encrypted ──────────────────────────────────────
resource "aws_sns_topic" "unencrypted_topic" {
  name              = "unencrypted-topic"
  kms_master_key_id = ""                   # no encryption
}

# ── 14. HIGH — ECR Repository Public + No Scan ────────────────────────────────
resource "aws_ecr_repository" "vulnerable_repo" {
  name                 = "vulnerable-repo"
  image_tag_mutability = "MUTABLE"         # tags can be overwritten

  image_scanning_configuration {
    scan_on_push = false                   # no vulnerability scanning
  }
}

# ── 15. HIGH — VPC Flow Logs Disabled ─────────────────────────────────────────
resource "aws_vpc" "insecure_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  # no flow logs configured              # network traffic not logged
}

# ── 16. MEDIUM — Secrets Manager Secret Not Rotated ──────────────────────────
resource "aws_secretsmanager_secret" "no_rotation" {
  name                    = "my-secret"
  recovery_window_in_days = 0            # immediate deletion, no recovery
}

resource "aws_secretsmanager_secret_version" "hardcoded" {
  secret_id     = aws_secretsmanager_secret.no_rotation.id
  secret_string = "hardcoded-plain-text-password-123"  # plaintext secret
}
