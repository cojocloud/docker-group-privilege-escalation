variable "region" {
  description = "AWS region to deploy the lab into."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name prefix applied to all resources, and the EC2 Name tag."
  type        = string
  default     = "privilege-escalation-lab"
}

variable "instance_type" {
  description = "EC2 instance type. t3.micro is Free Tier eligible in most accounts."
  type        = string
  default     = "t3.micro"
}

variable "key_name" {
  description = "Name of an existing EC2 key pair in this region, used for SSH access."
  type        = string
}

variable "allowed_ssh_cidr" {
  description = "CIDR block allowed to reach port 22, e.g. \"YOUR.IP.ADDRESS/32\". Never leave this as 0.0.0.0/0."
  type        = string

  validation {
    condition     = var.allowed_ssh_cidr != "0.0.0.0/0"
    error_message = "Do not open SSH to the entire internet. Set allowed_ssh_cidr to your own IP in CIDR notation (e.g. 203.0.113.10/32)."
  }
}
