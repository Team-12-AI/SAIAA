# ---------------------------------------------------------------------------
# OpenStack authentication
# ---------------------------------------------------------------------------
variable "cloud_name" {
  description = "Name of the OpenStack cloud env configured in clouds.yaml"
  type        = string
  default     = "ovhbhs5"
}


# ---------------------------------------------------------------------------
# Instance
# ---------------------------------------------------------------------------
variable "instance_count" {
  description = "Number of identical instances to create"
  type        = number
  default     = 2

  validation {
    condition     = var.instance_count >= 1 && var.instance_count <= 20
    error_message = "instance_count must be between 1 and 20."
  }
}

variable "instance_name" {
  description = "Name given to the VM instance (also used as a prefix for related resources)"
  type        = string
  default     = "ubuntu-2404-vm"
}

variable "image_name" {
  description = "Name of the Ubuntu 24.04 image in Glance"
  type        = string
  default     = "Ubuntu 24.04 - UEFI"
}

variable "image_id" {
    description = "ID of the image in Glance"
    type = string
}

variable "flavor_name" {
  description = "Compute flavor / size for the instance"
  type        = string
  default     = "d2-8"
}

variable "flavor_id" {
    description = "Compute flavor / size of the instance ID"
    type        = string
}

variable "environment_tag" {
  description = "Value for the 'environment' metadata tag"
  type        = string
  default     = "dev"
}

# ---------------------------------------------------------------------------
# Networking
# ---------------------------------------------------------------------------

variable "dns_nameservers" {
  description = "DNS servers assigned to the subnet"
  type        = list(string)
  default     = ["8.8.8.8", "8.8.4.4"]
}

variable "external_network_id" {
  description = "ID of the external / provider network used for the router gateway and floating IPs"
  type        = string
}

# ---------------------------------------------------------------------------
# SSH / access
# ---------------------------------------------------------------------------
variable "ssh_user" {
  description = "Default SSH user for Ubuntu cloud images"
  type        = string
  default     = "ubuntu"
}

variable "ssh_public_key_path" {
  description = "Path to the SSH public key file on the machine running Terraform"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "ssh_private_key_path" {
  description = "Path to the SSH private key file on the machine running Terraform"
  type        = string
  default     = "~/.ssh/id_rsa"
}

variable "ssh_allowed_cidr" {
  description = "CIDR that is allowed inbound SSH and ICMP access (restrict to your IP in production)"
  type        = string
  default     = "0.0.0.0/0"
}