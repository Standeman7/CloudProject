variable "aws_region" {
  default = "eu-west-1"
}

variable "bucket_name" {
  description = "Unique name for the app storage bucket"
  default     = "sve-application-file-storage-2025"
}

variable "db_table_name" {
  default = "file-metadata-2025"
}
variable "SSH_PUBLIC_KEY" {
  type = string
  default = null
}