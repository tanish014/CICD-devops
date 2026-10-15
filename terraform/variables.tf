variable "region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "ap-south-1"
}

variable "project" {
  description = "Name prefix applied to all resources"
  type        = string
  default     = "devops-platform"
}

variable "admin_cidr" {
  description = "Your public IP in CIDR form (e.g. 203.0.113.10/32). Only this range can reach SSH, Jenkins, the app, Grafana and Prometheus."
  type        = string

  validation {
    condition     = can(cidrhost(var.admin_cidr, 0)) && var.admin_cidr != "0.0.0.0/0"
    error_message = "admin_cidr must be a valid CIDR and must not be 0.0.0.0/0."
  }
}

variable "github_webhook_cidrs" {
  description = "Extra IPv4 CIDRs allowed to reach Jenkins :8080 so GitHub webhooks can arrive (see README). Leave empty to use SCM polling instead."
  type        = list(string)
  default     = []
}

variable "key_name" {
  description = "Name of an EXISTING EC2 key pair in the chosen region, used for SSH"
  type        = string
}

variable "cicd_instance_type" {
  description = "Instance type for EC2 #1 (Jenkins + Docker). t3.micro = 1 GB RAM (free-tier friendly)."
  type        = string
  default     = "t3.micro"
}

variable "app_instance_type" {
  description = "Instance type for EC2 #2 (k3s + app + Prometheus + Grafana). t3.micro is tight; use t3.small if it struggles."
  type        = string
  default     = "t3.small"
}

variable "cicd_volume_gb" {
  description = "Root volume size. 15 + 15 GB keeps two instances within the 30 GB EBS free allowance."
  type        = number
  default     = 15
}

variable "app_volume_gb" {
  type    = number
  default = 15
}
