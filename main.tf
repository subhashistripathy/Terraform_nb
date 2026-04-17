provider "aws" {
  region = "us-east-1"
}

# ─── S3: Private bucket with versioning & server-side encryption ───────────────
resource "aws_s3_bucket" "secure_bucket" {
  bucket = "secure-private-bucket"
}

resource "aws_s3_bucket_public_access_block" "secure_bucket_block" {
  bucket = aws_s3_bucket.secure_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "secure_bucket_sse" {
  bucket = aws_s3_bucket.secure_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "secure_bucket_versioning" {
  bucket = aws_s3_bucket.secure_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

# ─── Security Group: SSH restricted to a known CIDR ───────────────────────────
# Replace 203.0.113.0/32 with your actual trusted IP or bastion CIDR.
resource "aws_security_group" "restricted_ssh" {
  name        = "restricted-ssh-sg"
  description = "Allow SSH only from trusted IP"

  ingress {
    description = "SSH from trusted source"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["203.0.113.0/32"]   # ← replace with your IP
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ─── EC2: No public IP; place inside a private subnet ─────────────────────────
resource "aws_instance" "private_ec2" {
  ami                         = "ami-0c02fb55956c7d316"
  instance_type               = "t2.micro"
  associate_public_ip_address = false          # no public IP
  subnet_id                   = var.private_subnet_id
  vpc_security_group_ids      = [aws_security_group.restricted_ssh.id]

  metadata_options {
    http_tokens = "required"                   # enforce IMDSv2
  }

  tags = {
    Name = "private-ec2"
  }
}

# ─── RDS: Encrypted storage; credentials from Secrets Manager ─────────────────
data "aws_secretsmanager_secret_version" "db_creds" {
  secret_id = var.db_secret_id                 # secret ARN or name
}

locals {
  db_creds = jsondecode(data.aws_secretsmanager_secret_version.db_creds.secret_string)
}

resource "aws_db_instance" "secure_db" {
  allocated_storage       = 20
  engine                  = "mysql"
  engine_version          = "8.0"
  instance_class          = "db.t3.micro"
  username                = local.db_creds["username"]
  password                = local.db_creds["password"]
  skip_final_snapshot     = false
  final_snapshot_identifier = "secure-db-final-snapshot"
  storage_encrypted       = true               # encryption at rest
  multi_az                = true               # high availability
  publicly_accessible     = false              # no public endpoint
  deletion_protection     = true

  tags = {
    Name = "secure-db"
  }
}

# ─── EBS: Encrypted volume ────────────────────────────────────────────────────
resource "aws_ebs_volume" "encrypted_volume" {
  availability_zone = "us-east-1a"
  size              = 10
  encrypted         = true
  kms_key_id        = var.kms_key_arn          # customer-managed KMS key

  tags = {
    Name = "encrypted-volume"
  }
}

# ─── IAM: Least-privilege policy (example: read-only S3 on specific bucket) ───
# Replace with the minimum permissions your workload actually needs.
resource "aws_iam_policy" "least_privilege_policy" {
  name        = "least-privilege-policy"
  description = "Grants only the permissions this workload requires"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadSpecificBucket"
        Effect   = "Allow"
        Action   = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.secure_bucket.arn,
          "${aws_s3_bucket.secure_bucket.arn}/*"
        ]
      }
    ]
  })
}

# ─── Variables ────────────────────────────────────────────────────────────────
variable "private_subnet_id" {
  description = "ID of the private subnet for the EC2 instance"
  type        = string
}

variable "db_secret_id" {
  description = "ARN or name of the Secrets Manager secret containing DB credentials"
  type        = string
}

variable "kms_key_arn" {
  description = "ARN of the KMS key used to encrypt the EBS volume"
  type        = string
}
