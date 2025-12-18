# --- 1. Provider & Backend Configuration ---

terraform {
  # This connects your main project to the S3 bucket created in the 'setup' folder
  backend "s3" {
    bucket         = "sve-bucket-tfstate"
    key            = "dev/terraform.tfstate"
    region         = "eu-west-1"
    dynamodb_table = "terraform-lock-table"
    encrypt        = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "eu-west-1"
}

# --- 2. Key Pair for Ansible Access ---

# This registers your local public key with AWS so Ansible can log in via SSH
resource "aws_key_pair" "deployer" {
  key_name   = "deployer-key"
  public_key = var.SSH_PUBLIC_KEY
}
# --- 3. Ubuntu 24.04 LTS AMI ---

locals {
  ubuntu_ami = "ami-049442a6cf8319180" 
}

# --- 4. S3 & DynamoDB Resources (Application Data) ---

resource "aws_s3_bucket" "storage" {
  bucket        = "sve-application-file-storage-2025" 
  force_destroy = true
}

resource "aws_dynamodb_table" "metadata" {
  name         = "file-metadata-2025"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "filename"

  attribute {
    name = "filename"
    type = "S"
  }
}

# --- 5. IAM Role for EC2 ---

resource "aws_iam_role" "ec2_role" {
  name = "php_app_role_2025"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy" "ec2_policy" {
  name = "php_app_policy"
  role = aws_iam_role.ec2_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject", "s3:ListBucket"]
        Resource = ["${aws_s3_bucket.storage.arn}/*", "${aws_s3_bucket.storage.arn}"]
      },
      {
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem", "dynamodb:GetItem", "dynamodb:Scan", "dynamodb:Query", "dynamodb:DeleteItem"]
        Resource = aws_dynamodb_table.metadata.arn
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "php_instance_profile_2025"
  role = aws_iam_role.ec2_role.name
}

resource "aws_iam_role_policy_attachment" "ssm_managed_policy" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# --- 6. Security Group (Updated for Ansible/SSH) ---

resource "aws_security_group" "web_sg" {
  name        = "allow_web_traffic"
  description = "Allow HTTP and SSH inbound traffic"

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH for Ansible"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # For production, restrict this to your IP
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- 7. EC2 Instance ---

resource "aws_instance" "web_server" {
  ami                  = local.ubuntu_ami
  instance_type        = "t3.micro"
  key_name             = aws_key_pair.deployer.key_name
  iam_instance_profile = aws_iam_instance_profile.ec2_profile.name
  vpc_security_group_ids = [aws_security_group.web_sg.id]

  tags = {
    Name = "PHP-File-API"
  }

  # This block waits for the SSH port to be open before running Ansible
  provisioner "remote-exec" {
    inline = ["echo 'SSH is ready!'"]

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file("~/.ssh/id_rsa")
      host        = self.public_ip
    }
  }

  # This block triggers Ansible to configure the server
  provisioner "local-exec" {
    command = "ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i '${self.public_ip},' --private-key ~/.ssh/id_rsa -u ubuntu --extra-vars 'aws_region=${var.aws_region} app_bucket=${aws_s3_bucket.storage.id} app_table=${aws_dynamodb_table.metadata.name}' setup-app.yml"
}

}

resource "aws_eip" "web_eip" {
  domain = "vpc"
}

resource "aws_eip_association" "web_eip_assoc" {
  instance_id   = aws_instance.web_server.id
  allocation_id = aws_eip.web_eip.id
}

output "web_url" {
  value = format("http://%s", aws_eip.web_eip.public_ip)
}