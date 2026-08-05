module "vps" {
  source = "../../modules/vps-client"

  client_name      = var.client_name
  plan_id          = var.plan_id
  data_center_city = var.data_center_city
  template_name    = var.template_name
  ssh_public_key   = var.ssh_public_key
}
