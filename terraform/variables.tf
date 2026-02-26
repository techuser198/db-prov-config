variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP Region"
  type        = string
}

variable "zone" {
  description = "GCP Zone"
  type        = string
}

variable "machine_type" {
  description = "GCP Machine Type"
  type        = string
  default     = "e2-standard-4"
}

variable "boot_disk_size" {
  description = "Boot disk size in GB"
  type        = number
  default     = 50
}

variable "data_disk_size" {
  description = "Database data disk size in GB"
  type        = number
  default     = 100
}

variable "image" {
  description = "OS Image for the instance"
  type        = string
  # CentOS Stream 9 - Free, RHEL 9-compatible
  default     = "projects/centos-cloud/global/images/family/centos-stream-9"
}

variable "db_type" {
  description = "Database type (postgres only)"
  type        = string
  validation {
    condition     = var.db_type == "postgres"
    error_message = "Database type must be 'postgres'."
  }
}

variable "environment" {
  description = "Environment (dev, cert, prod)"
  type        = string
}

variable "customer" {
  description = "Customer code (AM, CP, NN, etc.)"
  type        = string
}

variable "ssh_user" {
  description = "SSH user for connecting to instances"
  type        = string
  default     = "devops"
}

variable "ssh_public_key_path" {
  description = "Path to SSH public key"
  type        = string
}

variable "ssh_private_key_path" {
  description = "Path to SSH private key"
  type        = string
}
