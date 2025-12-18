# Cloud Storage Infrastructure

This project uses Terraform to build AWS infra and Ansible to configure a PHP app.

## How to Deploy
1. **Prerequisites**: 
   - Install Terraform and Ansible locally.
   - Configure AWS CLI (`aws configure`).
   - Have an SSH key pair at `~/.ssh/id_rsa`.

2. **Step 1: Backend Setup**:
   - `cd setup`
   - `terraform init && terraform apply` (This creates your S3 state bucket).

3. **Step 2: Main Application**:
   - `cd ../main`
   - `terraform init`
   - `terraform apply` 
   - **Note**: This will automatically trigger Ansible to install PHP and the AWS SDK.

4. **Variables**:
   - Change `bucket_name` in `variables.tf` if the name is already taken.
5. **Using GITLAB CI/CD**:
   - Update the `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` in GitLab CI/CD variables for automated deployments.