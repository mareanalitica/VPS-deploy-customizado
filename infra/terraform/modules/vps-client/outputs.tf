output "server_id" {
  value = hostinger_vps.client.id
}

output "public_ipv4" {
  value = hostinger_vps.client.ipv4_address
}

output "public_ipv6" {
  value = hostinger_vps.client.ipv6_address
}
