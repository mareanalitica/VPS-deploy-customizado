variable "client_name" {
  description = "Identificador curto do cliente (kebab-case). Usado em nomes de recursos e labels."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,30}[a-z0-9]$", var.client_name))
    error_message = "client_name deve ser kebab-case, 3-32 caracteres, so [a-z0-9-]."
  }
}

variable "plan_id" {
  description = <<-EOT
    ID do plano Hostinger VPS (ex: "hostingercom-vps-kvm2-usd-1m").
    Descubra o valor exato rodando a data source hostinger_vps_plans - ver
    infra/terraform/README.md.
  EOT
  type        = string
}

variable "data_center_city" {
  description = <<-EOT
    Cidade do datacenter Hostinger desejado (ex: "Sao Paulo", "Vilnius").
    Precisa bater EXATAMENTE com o campo "city" retornado pela data source
    hostinger_vps_data_centers.
  EOT
  type        = string
}

variable "template_name" {
  description = <<-EOT
    Nome exato do template de SO (ex: "Ubuntu 24.04 LTS"). Precisa bater
    EXATAMENTE com o campo "name" retornado pela data source
    hostinger_vps_templates.
  EOT
  type        = string
}

variable "ssh_public_key" {
  description = "Conteudo (nao caminho) da chave publica SSH autorizada a acessar a VPS."
  type        = string
}
