resource "hostinger_vps_ssh_key" "client" {
  name = "${var.client_name}-deploy-key"
  key  = var.ssh_public_key
}

data "hostinger_vps_data_centers" "all" {}
data "hostinger_vps_templates" "all" {}

locals {
  matching_data_center_ids = [
    for dc in data.hostinger_vps_data_centers.all.data_centers :
    dc.id if dc.city == var.data_center_city
  ]

  matching_template_ids = [
    for t in data.hostinger_vps_templates.all.templates :
    t.id if t.name == var.template_name
  ]

  data_center_id = try(one(local.matching_data_center_ids), null)
  template_id    = try(one(local.matching_template_ids), null)
}

resource "hostinger_vps" "client" {
  plan           = var.plan_id
  data_center_id = local.data_center_id
  template_id    = local.template_id
  hostname       = "${var.client_name}.vps.internal"
  ssh_key_ids    = [hostinger_vps_ssh_key.client.id]

  # Sem "password": deixamos o Hostinger gerar uma senha de root aleatoria
  # que nunca usamos - acesso e' so por chave SSH. A role "hardening" do
  # Ansible desabilita PasswordAuthentication no sshd por cima disso.

  lifecycle {
    prevent_destroy = true

    precondition {
      condition = local.data_center_id != null
      error_message = join("", [
        "Nenhum datacenter Hostinger com city = \"${var.data_center_city}\" foi encontrado. ",
        "Valores validos de 'city' para esta conta: ",
        join(", ", [for dc in data.hostinger_vps_data_centers.all.data_centers : dc.city]),
        "."
      ])
    }

    precondition {
      condition = local.template_id != null
      error_message = join("", [
        "Nenhum template Hostinger com name = \"${var.template_name}\" foi encontrado. ",
        "Valores validos de 'name' para esta conta: ",
        join(", ", [for t in data.hostinger_vps_templates.all.templates : t.name]),
        "."
      ])
    }
  }
}
