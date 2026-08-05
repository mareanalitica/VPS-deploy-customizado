# Terraform — Provisionamento de VPS por Cliente

Cada cliente novo recebe **uma VPS Hostinger isolada e dedicada** (não é
multi-tenant). Isso mantém dados/segredos de clientes diferentes totalmente
apartados e mantém o modelo de segurança simples (mesma superfície de
ataque de sempre, só que por cliente).

## Estrutura

```
infra/terraform/
  modules/vps-client/    <- módulo reutilizável (VPS Hostinger + SSH key)
  clients/
    _template/            <- copie esta pasta para cada cliente novo
    <nome-do-cliente>/     <- uma pasta real por cliente (gitignored, exceto _template)
```

## Pré-requisito: token de API da Hostinger

Gere em **hPanel → conta → API** (leia [Getting started with the Hostinger
Terraform provider](https://www.hostinger.com/support/11080294-getting-started-with-the-hostinger-terraform-provider/)).
O provider lê o token da env var `HOSTINGER_API_TOKEN` — nunca coloque o
token em `terraform.tfvars`.

## Onboarding de um cliente novo

```bash
cp -r infra/terraform/clients/_template infra/terraform/clients/acme
cd infra/terraform/clients/acme

cp terraform.tfvars.example terraform.tfvars   # preencha client_name, ssh_public_key
cp backend.tf.example backend.tf               # escolha S3-compatible OU Terraform Cloud, descomente UM bloco

export HOSTINGER_API_TOKEN="..."

terraform init
```

Você **não precisa** descobrir os valores de `data_center_city`/
`template_name` antes de rodar `terraform plan` — o módulo resolve esses
nomes para o ID correto internamente (`modules/vps-client/main.tf`) e, se
não encontrar nada com esse nome exato, o `precondition` do recurso falha
o `plan`/`apply` mostrando a lista de valores válidos daquela conta direto
na mensagem de erro. Ou seja: tente um valor razoável, rode `terraform
plan`, e corrija com base no erro se necessário.

Só `plan_id` não tem essa rede de segurança embutida (é passado direto pra
API, sem lookup por nome) — para descobrir os planos disponíveis:

```bash
terraform console
> data.hostinger_vps_plans.all.plans
```

```bash
terraform plan     # revise antes de aplicar
terraform apply
terraform output -json > .terraform-outputs.json   # consumido pelo gerador de inventario do Ansible
```

## ⚠️ Firewall de nuvem: automatizado via Ansible, não via Terraform

O provider `hostinger/hostinger` (v0.1.x) **não expõe um recurso Terraform
para o Firewall gerenciado da Hostinger** — só `hostinger_vps`,
`hostinger_vps_ssh_key`, `hostinger_vps_post_install_script` e
`hostinger_dns_record`. A API REST da Hostinger (a que o provider usa por
baixo) **tem** endpoints de firewall, então isso é configurado pela role
Ansible `hostinger_firewall` chamando a API diretamente — não é um passo
manual, mas também não é Terraform. Detalhes, incluindo a incerteza
conhecida sobre alguns valores de campo, em
[infra/ansible/README.md](../ansible/README.md#%EF%B8%8F-sobre-a-role-hostinger_firewall).

Isso é uma camada **adicional** à proteção que já existe no host via
`setup/security/harden-vps.sh` (UFW + fail2ban + SSH key-only + chain
`DOCKER-USER`) — mesmo que a chamada à API do firewall falhe ou fique
desatualizada, a VPS não fica aberta, só perde uma camada de defesa em
profundidade antes do pacote chegar no host. Ver
[ADR 0004](../../docs/adr/0004-terraform-ansible-replication.md) para o
racional completo.

## Por que não backend local?

O state local (`terraform.tfstate` no disco) não tem lock nem histórico —
se o laptop de quem rodou `terraform apply` sumir, ninguém mais consegue
saber o que existe de verdade na nuvem, e um `apply` concorrente de duas
pessoas pode corromper o state. `backend.tf.example` traz duas opções
prontas (S3-compatível ou Terraform Cloud); escolha uma antes do primeiro
`terraform apply` real.

## Decomissionando um cliente

`hostinger_vps` tem `lifecycle { prevent_destroy = true }` de propósito —
`terraform destroy` sozinho não apaga a VPS. Para decomissionar de verdade:
1. Confirme que o backup mais recente (`npm run backup:volumes` rodado via
   Ansible) foi copiado para fora da VPS.
2. Remova o bloco `lifecycle` em `modules/vps-client/main.tf`
   **localmente** (não precisa commitar) e então rode `terraform destroy`.
3. Apague o grupo de firewall correspondente no hPanel (passo manual, ver
   seção acima).
4. Apague a pasta `infra/terraform/clients/<nome>` do repo depois de
   confirmado.

## Outros provedores de nuvem

O módulo `modules/vps-client` hoje só suporta Hostinger. Para adicionar
outro provedor no futuro (Hetzner, DigitalOcean, AWS), crie um módulo
irmão (ex: `modules/vps-client-hetzner`) com o mesmo contrato de
entrada/saída (`client_name`, `ssh_public_key` → `server_id`,
`public_ipv4`, `public_ipv6`) — os clientes em `clients/<nome>/main.tf`
trocam só a linha `source` do `module "vps"`.
