output "instance_public_ipv4" {
  value       = openstack_compute_instance_v2.vm[*].access_ip_v4
  description = "The public IPv4 address of the main server instance."
}

output "instance_public_ipv6" {
  value       = openstack_compute_instance_v2.vm[*].access_ip_v6
  description = "The public IPv6 address of the main server instance."
}