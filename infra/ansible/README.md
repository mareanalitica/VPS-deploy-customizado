# Ansible — Configuração Idempotente da VPS do Cliente

Roda depois que a VPS já existe (`terraform apply` em
`infra/terraform/clients/<nome>/` — ver [../terraform/README.md](../terraform/README.md)).

## Pré-requisitos (uma vez, na máquina que vai rodar o Ansible)

```bash
pip install ansible
ansible-galaxy collection install -r infra/ansible/requirements.yml
```

Exporte o mesmo token usado pelo Terraform (a role `hostinger_firewall`
chama a API da Hostinger diretamente, roda no control node):

```bash
export HOSTINGER_API_TOKEN="..."
```

## Onboarding de um cliente novo

```bash
cd infra/ansible
cp group_vars/all.yml.example group_vars/all.yml   # preencha repo_git_url, domain_name, etc.
# Opcional: infra/ansible/host_vars/<client_name>.yml para sobrescrever algo so para este cliente.

ansible-playbook site.yml --limit <client_name>
```

O inventário (`inventory/terraform_inventory.py`) é dinâmico: ele lê
`terraform output -json` de cada pasta em `infra/terraform/clients/` na
hora, então não precisa manter nenhum arquivo de inventário sincronizado à
mão. Rode `python3 inventory/terraform_inventory.py --list` para conferir o
que ele está vendo antes de rodar o playbook de verdade.

## O que o `site.yml` faz, em ordem

0. **`hostinger_firewall`** (roda no control node, não na VPS) — chama a
   API REST da Hostinger diretamente (`POST/PUT /api/vps/v1/firewall/...`)
   para criar/atualizar o grupo de firewall gerenciado deste cliente e
   ativá-lo na VPS, restringindo a porta 22 aos CIDRs de
   `admin_allowed_cidrs` e liberando 80/443. **Best-effort**: os valores de
   enum (`protocol`/`source`) usados nas chamadas não puderam ser 100%
   confirmados contra a especificação OpenAPI real nesta implementação —
   ver `roles/hostinger_firewall/defaults/main.yml` e a nota abaixo.
1. **Sincroniza o repo** na VPS (`git clone`/`pull` em `deploy_root`, default `/opt/vps-deploy`).
2. **`docker`** — instala Docker Engine e Node.js via repositórios apt oficiais
   com GPG verificado (substitui o antigo `curl | sh` do `setup/init.sh`),
   inicializa o Swarm, cria a rede `public_net`.
3. **`hardening`** — roda `setup/security/harden-vps.sh` (UFW, fail2ban,
   SSH key-only, sysctl, chain `DOCKER-USER`). Roda depois do Docker de
   propósito, senão a proteção da chain `DOCKER-USER` fica pulada na
   primeira passada.
4. **`secrets`** — roda `setup/scripts/manage-env.js` (gera senhas
   aleatórias para chaves vazias) e ajusta os valores não-secretos
   específicos deste cliente (`DOMAIN_NAME`, `ADMIN_ALLOWED_CIDRS`, etc.) no
   `.env` gerado.
5. **`stack_deploy`** — roda `setup/scripts/deploy.sh` (cria os Docker
   Secrets a partir do `.env`, builda a imagem customizada do Jenkins, faz o
   `docker stack deploy`) e espera o container do Traefik ficar `healthy`.
6. **`backup`** — agenda o backup diário (`backup-volumes.sh`) via cron; se
   `backup_remote_rclone_target` estiver definido, também envia a cópia mais
   recente para um destino remoto via `rclone` (ver nota de criptografia
   abaixo).

### ⚠️ Sobre a role `hostinger_firewall`

O provider Terraform da Hostinger não expõe firewall como recurso, mas a
API REST da Hostinger tem (`developers.hostinger.com`, endpoints
`/api/vps/v1/firewall*`). Confirmei os endpoints e os *nomes* dos campos de
uma regra (`protocol`, `port`, `source`, `source_detail`) contra a
documentação oficial do SDK Python da Hostinger. Existe uma segunda fonte
(um repositório de "skills" de terceiros, não-oficial) descrevendo um
formato diferente para o mesmo corpo de requisição
(`protocol`/`port`/`source`/`action`, sem `source_detail`) — decisão
deliberada: confiar na doc oficial do SDK, não na fonte de terceiros.

Dentro desse formato escolhido, ainda **não confirmei os valores exatos
aceitos** por `protocol`/`source` (a especificação OpenAPI completa é
grande demais para eu extrair só essa seção com confiança nesta sessão).
Na primeira execução real:
- Se a API aceitar os defaults (`TCP`/`any_ip`/`custom`), ótimo, segue.
- Se rejeitar (status 400/422), a resposta da própria Hostinger deve
  listar os valores aceitos — ajuste `hostinger_firewall_protocol` /
  `hostinger_firewall_source_open` / `hostinger_firewall_source_restricted`
  em `group_vars/all.yml` (ou `roles/hostinger_firewall/defaults/main.yml`)
  com base nisso.

Isso não deixa a VPS exposta enquanto não for corrigido: é uma camada
*adicional* ao hardening do host (UFW/fail2ban/`DOCKER-USER`/SSH-só-chave),
que já roda independentemente e é a proteção primária.

Cada role reaproveita os scripts já revisados na auditoria de segurança
(Fase 1/2) em vez de reimplementar a mesma lógica em módulos nativos do
Ansible — assim não existem duas versões da mesma lógica para manter
sincronizadas.

## Sobre o backup remoto (`rclone`)

A role `backup` instala e agenda o `rclone`, mas **não configura
credenciais** — isso exige acesso à conta/bucket real de destino, então é
um passo manual: `rclone config` na VPS (ou copie um `rclone.conf` pronto)
antes do primeiro cron rodar. A cópia enviada não é criptografada em
repouso no destino por padrão — para isso, configure um remote `crypt` do
rclone por cima do remote real. Ver comentário em
`roles/backup/templates/backup-and-push.sh.j2`.

## Testando sem gastar uma VPS real

Não há cobertura via Molecule neste momento — o ambiente onde este código
foi escrito não tinha Ansible/Docker-in-Docker disponível para validar os
cenários de teste, e cenários de Molecule não executados são só uma falsa
sensação de segurança. O `--syntax-check` roda sem custo:

```bash
ansible-playbook site.yml --syntax-check
```

A pipeline de CI (`.github/workflows/infra-lint.yml`) roda `ansible-lint`
em todo PR que toque `infra/ansible/` — essa é a rede de segurança real até
que exista cobertura Molecule (fica como próximo passo recomendado).
