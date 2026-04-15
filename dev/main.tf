terraform {
  required_version = ">= 1.3.0"

  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 1.54"
    }
  }
}

# ---------------------------------------------------------------------------
# Provider – credentials are read from variables (or OS_* env vars)
# ---------------------------------------------------------------------------
provider "openstack" {
    cloud = var.cloud_name
}

# ---------------------------------------------------------------------------
# Data sources
# ---------------------------------------------------------------------------
data "openstack_images_image_v2" "ubuntu_2404" {
  name        = var.image_name
  most_recent = true
}

data "openstack_compute_flavor_v2" "vm_flavor" {
  name = var.flavor_name
}

# ---------------------------------------------------------------------------
# Key pair
# ---------------------------------------------------------------------------
resource "openstack_compute_keypair_v2" "vm_keypair" {
  name       = "${var.instance_name}-keypair"
  public_key = file(var.ssh_public_key_path)
}

# ---------------------------------------------------------------------------
# Compute instance
# ---------------------------------------------------------------------------

resource "openstack_compute_instance_v2" "vm" {
  count           = var.instance_count
  name            = "var.instance_name-${count.index}"
  image_id        = data.openstack_images_image_v2.ubuntu_2404.id
  flavor_id       = data.openstack_compute_flavor_v2.vm_flavor.id
  key_pair        = openstack_compute_keypair_v2.vm_keypair.name
  security_groups = ["default"]

  # Cloud-init: set hostname and configure SSH
  user_data = <<-EOF
    #cloud-config
    hostname: ${var.instance_name}
    manage_etc_hosts: true
    ssh_pwauth: false
    package_update: true
  EOF

  network {
    uuid = var.external_network_id
  }

  connection {
    type        = "ssh"
    host        = self.access_ip_v4
    user        = var.ssh_user
    private_key = file(var.ssh_private_key_path)
    timeout     = "5m"
  }

  provisioner "remote-exec" {
    inline = [
      # Wait for cloud-init to finish 
      "cloud-init status --wait || true",

      # Refresh package index 
      "sudo apt-get update -y",

      # Install prerequisites 
      "sudo apt-get install -y software-properties-common",

      # Refresh package index 
      "sudo apt-get update -y",

      # Install git and vim and snap and jq
      "sudo apt-get install -y git vim snapd jq",

      # Refresh package index 
      "sudo apt-get update -y",

      # Add Ansible PPA
      "sudo add-apt-repository --yes --update ppa:ansible/ansible",

      # Refresh package index 
      "sudo apt-get update -y",

      # Install Ansible
      "sudo apt-get install -y ansible",

      # Refresh package index 
      "sudo apt-get update -y",
      
      # Clone the ZeroClaw repository 
      "git clone https://github.com/zeroclaw-labs/zeroclaw.git",

      # Clone the MCPJungle repository
      "git clone https://github.com/mcpjungle/MCPJungle.git",

      # Make ansible directory
      "mkdir -p /home/${var.ssh_user}/ansible"
    ]
  }

  provisioner "file" {
    source      = "ansible/ssh_keys.yml"
    destination = "/home/${var.ssh_user}/ansible/ssh_keys.yml"
  }

  provisioner "file" {
    source      = "ansible/playbook.yml"
    destination = "/home/${var.ssh_user}/ansible/playbook.yml"
  }

  provisioner "file" {
    source      = "ansible/requirements.yml"
    destination = "/home/${var.ssh_user}/ansible/requirements.yml"
  }

  provisioner "file" {
    source      = "ansible/brock.pub"
    destination = "/home/${var.ssh_user}/ansible/brock.pub"
  }

  provisioner "file" {
    source      = "ansible/docker-compose.yml"
    destination = "/home/${var.ssh_user}/docker-compose.yml"
  }

  provisioner "remote-exec" {
    inline = [
      # Refresh package index 
      "sudo apt-get update -y",

      # Set permissions for Ansible scripts
      "chmod -R +x /home/${var.ssh_user}/ansible",

      # Configure SSH ssh_keys
      "/home/${var.ssh_user}/ansible/ssh_keys.yml",

      # Set permissions for Ansible scripts
      "sudo ansible-galaxy install -r /home/${var.ssh_user}/ansible/requirements.yml",

      # Install and configure Docker
      "sudo /home/${var.ssh_user}/ansible/playbook.yml",
    ]
  }

  metadata = {
    environment = var.environment_tag
    managed_by  = "terraform"
  }
}