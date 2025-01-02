variable "region" {
  type        = string
  description = "Region from script"
  default     = "eu-north-1"
}

variable "ami" {
  type        = string
  description = "AMI from iso"
  default     = "default"
}

variable "allowed_ssh_ips" {
  type = list(string)
  description = "Allowed ip addresses"
  default = ["0.0.0.0/0"]
}

variable "key_name" {
  type = string
  description = "Name of the ssh key"
  default = "eranssh"
}