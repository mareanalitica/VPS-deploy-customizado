terraform {
  required_version = ">= 1.5.0"

  required_providers {
    hostinger = {
      source  = "hostinger/hostinger"
      version = "~> 0.1"
    }
  }

  # Backend remoto: copie backend.tf.example para backend.tf e preencha.
  # NUNCA use backend local (default) para um cliente real - o state contem
  # IDs de recursos reais e fica sem historico/lock se o disco do laptop
  # sumir. Ver infra/terraform/README.md.
}

provider "hostinger" {
  # Token lido de HOSTINGER_API_TOKEN (env var) - nunca commitar em .tfvars.
  # Gere em hPanel -> API do seu perfil/conta Hostinger.
}
