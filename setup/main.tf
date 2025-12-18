# setup/main.tf (Run this in the 'setup' directory FIRST)

terraform {
    required_providers {
        aws = {
            source  = "hashicorp/aws"
            version = "~> 4.0"
        }
    }
}

provider "aws" {
    region = "eu-west-1"
}

# 1. S3 BUCKET for Terraform State
resource "aws_s3_bucket" "tfstate_bucket" {
    bucket = "sve-bucket-tfstate" 

    versioning {
        enabled = true
    }

    server_side_encryption_configuration {
        rule {
            apply_server_side_encryption_by_default {
                sse_algorithm = "AES256"
            }
        }
    }

    tags = {
        Name = "Terraform-State-Backend-Bucket"
    }
}

# 2. Block All Public Access (Security Best Practice)
resource "aws_s3_bucket_public_access_block" "tfstate_public_access" {
    bucket                  = aws_s3_bucket.tfstate_bucket.id
    block_public_acls       = true
    block_public_policy     = true
    ignore_public_acls      = true
    restrict_public_buckets = true
}

# 3. DYNAMODB TABLE for State Locking
resource "aws_dynamodb_table" "terraform_locks" {
    name           = "terraform-lock-table" 
    billing_mode   = "PAY_PER_REQUEST"
    hash_key       = "LockID" # Required key name for S3 backend

    attribute {
        name = "LockID"
        type = "S" 
    }
    
    tags = {
        Name = "Terraform-State-Locking-Table"
    }
}