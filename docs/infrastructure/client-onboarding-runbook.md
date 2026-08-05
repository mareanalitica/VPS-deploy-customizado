# 🧭 Runbook: Onboarding de um Cliente Novo (VPS Dedicada)

[← Voltar para o Hub de Documentação](../README.md)

Passo a passo real para colocar um cliente novo no ar usando Terraform +
Ansible. Cada cliente recebe **uma VPS Hostinger isolada** — nunca
multi-tenant (ver [ADR 0004](../adr/0004-terraform-ansible-replication.md)).

⚠️ **"No ar" tem duas camadas, não confunda uma com a outra:**
1. **Infraestrutura** (Traefik, Portainer, Jenkins, bancos, n8n) — sobe
   sozinha nos passos 1-2 abaixo, via Terraform + Ansible.
2. **A aplicação do cliente** (`api-nestjs`, `web-vite`) — **não sobe
   sozinha**. O domínio principal do cliente só responde com algo depois
   do passo 5 (criar o job no Jenkins e rodar o primeiro build). Até lá, a
   infra está de pé mas o site do cliente ainda não existe atrás do
   domínio.

---

## Checklist: dados e recursos a coletar ANTES de começar

### Do cliente

| # | O quê | Onde é usado | Obrigatório? |
|---|---|---|---|
| 1 | Nome/identificador curto do projeto (kebab-case, ex: `acme`) | `client_name` (Terraform + Ansible) | Sim |
| 2 | Domínio do cliente (ex: `acme.com`) | `domain_name` (`.env`, rotas do Traefik) | Sim |
| 3 | Acesso ao painel de DNS do domínio — ou alguém do lado do cliente disposto a criar os registros que você passar | Passo 4 (DNS) | Sim |
| 4 | URL do repositório Git com o código da aplicação (e credencial de acesso, se for privado) | `repo_git_url` (Ansible), checkout do Jenkins | Sim |
| 5 | IP(s)/CIDR(s) fixo(s) de quem vai administrar (time do cliente e/ou da agência) | `ADMIN_ALLOWED_CIDRS` (Traefik + firewall Hostinger) | Sim — sem isso os painéis administrativos ficam inacessíveis por padrão (fail-closed) |
| 6 | E-mail técnico de contato (pode ser da agência) | `traefik_acme_email` (avisos do Let's Encrypt) | Sim |

### Da agência / operador (decisão técnica, não vem do cliente)

| # | O quê | Onde é usado | Obrigatório? |
|---|---|---|---|
| 7 | Token de API da Hostinger (hPanel → conta → API) | `HOSTINGER_API_TOKEN` (Terraform + role `hostinger_firewall`) | Sim |
| 8 | Par de chaves SSH dedicado para deploy | `ssh_public_key` (Terraform) | Sim |
| 9 | Datacenter (`data_center_city`), plano (`plan_id`) e template de SO (`template_name`) da VPS | `terraform.tfvars` | Sim |
| 10 | Backend remoto do Terraform state (bucket S3-compatível ou Terraform Cloud) já criado | `backend.tf` | Sim — nunca use state local para um cliente real |
| 11 | Destino remoto de backup + credenciais (ex: Hetzner Storage Box, S3, R2) | `backup_remote_rclone_target` + `rclone config` na VPS | Opcional — sem isso, backup fica só local na própria VPS |
| 12 | Payment method ID da Hostinger, se o cliente não usa o método de pagamento padrão da conta | `payment_method_id` (não usado no módulo atual — ver nota abaixo) | Opcional |

> O módulo Terraform atual (`infra/terraform/modules/vps-client`) não expõe `payment_method_id` — se precisar, é um `var` a mais para adicionar em `variables.tf`/`main.tf`.

---

## 0. Pré-requisitos (uma vez por máquina operadora)

```bash
pip install ansible ansible-lint
ansible-galaxy collection install -r infra/ansible/requirements.yml
# Instale o Terraform CLI: https://developer.hashicorp.com/terraform/install
```

Você também precisa de:
- Um token de API da Hostinger (hPanel → conta → API — ver [infra/terraform/README.md](../../infra/terraform/README.md)).
- Um par de chaves SSH dedicado para deploy (`ssh-keygen -t ed25519 -f ~/.ssh/acme-deploy`).
- Um backend remoto de state já decidido (S3-compatível ou Terraform Cloud — ver [infra/terraform/README.md](../../infra/terraform/README.md)).

## 1. Provisionar a VPS (Terraform)

```bash
make client-scaffold CLIENT=acme
cd infra/terraform/clients/acme
cp terraform.tfvars.example terraform.tfvars   # preencha
cp backend.tf.example backend.tf               # descomente UM backend

export HOSTINGER_API_TOKEN="..."
terraform init
```

Preencha `data_center_city`/`template_name` com um valor razoável (ex:
`"Sao Paulo"`, `"Ubuntu 24.04 LTS"`) e siga — o módulo valida esses dois
sozinho no `plan`/`apply` e, se errar, o erro já lista os valores válidos
daquela conta. Só `plan_id` precisa ser consultado manualmente antes (ver
[infra/terraform/README.md](../../infra/terraform/README.md)).

```bash
cd ../../../..
make client-plan CLIENT=acme     # revise o plano
```

Se o plano estiver correto:

```bash
cd infra/terraform/clients/acme && terraform apply
```

### ⚠️ Firewall gerenciado (automático, via Ansible)

O provider Terraform da Hostinger ainda não expõe o Firewall gerenciado da
plataforma como recurso — mas o passo 2 abaixo (`make client-configure`)
já cuida disso via chamada direta à API da Hostinger (role
`hostinger_firewall`), restringindo a porta 22 aos IPs em
`ADMIN_ALLOWED_CIDRS`. Alguns valores de campo dessa chamada são
best-effort (ver [infra/ansible/README.md](../../infra/ansible/README.md#%EF%B8%8F-sobre-a-role-hostinger_firewall))
— confira o output dessa etapa na primeira execução real de um cliente.

## 2. Configurar a VPS (Ansible)

```bash
cd infra/ansible
cp group_vars/all.yml.example group_vars/all.yml   # preencha domain_name, repo_git_url etc.
cd ../..

make client-configure CLIENT=acme
```

Isso instala Docker+Node (repositório oficial, sem `curl | sh`), aplica o
hardening (UFW/fail2ban/DOCKER-USER), gera os segredos, builda a imagem do
Jenkins e faz o `docker stack deploy` — detalhes em
[infra/ansible/README.md](../../infra/ansible/README.md).

`make client-new CLIENT=acme` faz os passos 1 e 2 em sequência, se você já
revisou o `terraform plan` e confia no fluxo padrão.

## 3. DNS

Aponte os registros do domínio do cliente para o `public_ipv4` do output do
Terraform (`terraform output public_ipv4` dentro da pasta do cliente).
Aponte TODOS de uma vez, mesmo os que ainda não têm nada rodando atrás
(o Traefik só tenta emitir certificado quando alguém de fato acessa/existe
um router para aquele host):

- `jenkins.<domínio>`, `portainer.<domínio>`, `rabbitmq.<domínio>`, `minio.<domínio>`, `s3.<domínio>`, `n8n.<domínio>` — já têm router no `docker-stack.yml`, funcionam assim que a infra sobe (passo 2).
- `<domínio>` (e `api.<domínio>`, se a API tiver subdomínio próprio) — só passam a ter algo por trás depois do passo 5 (deploy da aplicação); aponte o DNS agora mesmo assim, para não esquecer depois.

O Traefik só emite certificado Let's Encrypt depois que o DNS resolver de
verdade (desafio HTTP-01) **e** existir um router com aquele `Host(...)` —
para os subdomínios de infra isso já acontece no passo 2; para o domínio
principal, só no passo 5.

## 4. Verificação pós-deploy (só a infraestrutura)

```bash
ssh root@<ip> "docker service ls"          # todos os serviços 'infra_*' com replicas 1/1
curl -I https://jenkins.<domínio>           # 403 se seu IP nao estiver em ADMIN_ALLOWED_CIDRS - esperado
```

Do IP configurado em `ADMIN_ALLOWED_CIDRS`, `jenkins.<domínio>` e
`portainer.<domínio>` devem responder normalmente. **Não teste
`https://<domínio>` ainda** — nesta etapa não existe nenhum router do
Traefik apontando pra ele (só sobem `jenkins.`/`portainer.`/`rabbitmq.`/
`minio.`/`s3.`/`n8n.`, que já vêm com labels no `docker-stack.yml`), então
um 404 aqui é esperado e não indica erro.

## 5. Primeiro deploy de aplicação (o que falta pro domínio principal responder)

✅ Gap fechado: [`apps-stack.yml`](../../setup/docker/apps-stack.yml) define
os serviços `api-nestjs`/`web-vite` (rede, secrets, labels do Traefik para
`api.<domínio>`/`<domínio>`), e o `Jenkinsfile.template` (estágio 4) já
aponta pro nome real do serviço no Swarm (`apps_api-nestjs`, não mais
`${APP_NAME}_service`, que nunca existiu).

1. Garanta `DEPLOY_APPS_STACK=1` no `.env` do cliente e rode
   `make client-configure` (ou `bash setup/scripts/deploy.sh` direto na
   VPS) pelo menos uma vez — isso sobe a stack `apps` inicial e roda o
   [bootstrap de bancos dedicados](../../setup/scripts/bootstrap-app-databases.sh).
2. Crie os *jobs* no Jenkins (login com `JENKINS_ADMIN_USER` / senha do
   secret `jenkins_admin_password`) apontando para o `Jenkinsfile.template`
   de cada app. A partir do primeiro build, o Jenkins passa a atualizar o
   serviço já existente via `docker service update --image`.

## 6. Confirmação final: o cliente vê tudo no ar?

```bash
curl -I https://<domínio>                   # 200, certificado valido - só depois do passo 5
curl -I https://api.<domínio>                # idem, se a API tiver rota propria
```

Só marque o onboarding como concluído quando os dois grupos abaixo
responderem certo:

- **Infra** (passo 4): `jenkins.`/`portainer.`/`rabbitmq.`/`minio.`/`s3.`/`n8n.` respondendo do IP autorizado.
- **Aplicação** (passo 5): `<domínio>` e subdomínios da app com certificado válido e a aplicação de fato respondendo (não um 404 do Traefik).

## 7. Decomissionamento

Ver [infra/terraform/README.md § Decomissionando um cliente](../../infra/terraform/README.md#decomissionando-um-cliente).
