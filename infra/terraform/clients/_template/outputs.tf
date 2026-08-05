output "server_id" {
  value = module.vps.server_id
}

output "public_ipv4" {
  value = module.vps.public_ipv4
}

output "public_ipv6" {
  value = module.vps.public_ipv6
}

output "client_name" {
  value = var.client_name
}
