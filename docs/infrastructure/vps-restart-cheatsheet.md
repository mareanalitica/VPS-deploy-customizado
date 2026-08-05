# 🧭 Colinha: VPS Reiniciou — E Agora?

[← Voltar para o Hub de Documentação](../README.md)

Guia rápido pra quando você precisar reconectar/reconfigurar a VPS do
cliente `mare` (ou qualquer outro cliente seguindo o mesmo padrão). Baseado
em problemas reais que já mordemos numa sessão de debug ao vivo.

---

## Cenário 1: Reboot normal (a VPS reiniciou, mas o disco continua o mesmo)

Não precisa fazer nada de especial — Docker/Swarm/serviços sobem sozinhos
(systemd + Swarm reconectam automaticamente). Só confirme:

```bash
ssh -i ~/.ssh/mare-deploy root@IP
docker service ls
```

Se tudo estiver `N/N` (réplicas batendo), está tudo certo. Se algo estiver
`0/N`, veja a seção **Diagnóstico rápido** abaixo.

---

## Cenário 2: Reset de SO pelo hPanel (apaga TUDO — disco, chaves, senha)

### 1-4. Reconfigurar o acesso SSH por chave

Guia completo (limpar `known_hosts`, reconectar com senha, autorizar sua
chave, testar): [SSH First Access](./ssh-first-access.md).

### 5. Rodar o playbook (do WSL, onde o Ansible está instalado)
```bash
source ~/.venvs/ansible/bin/activate
cd /mnt/c/Users/dev/projetos/linkedin/01-deploy/infra/ansible
export HOSTINGER_API_TOKEN="..."
ansible-playbook -i inventory/hosts.yml site.yml --limit mare --skip-tags hostinger_firewall
```
(`--skip-tags hostinger_firewall` porque decidimos configurar o firewall
gerenciado da Hostinger separadamente — ver [ADR 0004](../adr/0004-terraform-ansible-replication.md).)

---

## Diagnóstico rápido

```bash
docker service ls                                  # visão geral - o que esta' 0/N?
docker service ps infra_<nome> --no-trunc           # por que um servico especifico falhou
docker logs $(docker ps -q -f name=infra_<nome>)    # logs do container rodando agora
grep <VARIAVEL> /opt/vps-deploy/.env                # confere se uma env var tem valor "grudado" antigo
cd /opt/vps-deploy && git log -1 --format="%H %s"   # confirma que o clone na VPS esta atualizado
```

## Armadilhas que já mordemos (pra não perder tempo de novo)

| Sintoma | Causa | Fix |
|---|---|---|
| Serviço reclama de imagem/config "not found" ou usa conteúdo antigo mesmo após corrigir o arquivo | **Docker Secrets e Configs do Swarm são imutáveis** — não dá pra atualizar o conteúdo, só criar um novo com nome diferente | Bump a versão no nome (`jenkins_init_v2` → `_v3`) **nos dois lugares** do `docker-stack.yml` (referência no serviço + definição no bloco `configs:`/`secrets:`) |
| Uma variável no `.env` da VPS tem um valor que "não devia mais existir" | `manage-env.js` **nunca remove** chaves antigas do `.env`, só preenche as vazias | `sed -i '/^VARIAVEL=/d' .env` direto na VPS, ou editar manualmente |
| Comando manual funciona diferente do que o Ansible faz | Sessão SSH manual **acumula variáveis exportadas** de comandos anteriores (`set -a; . .env`) — o Ansible sempre abre conexão nova, então nunca sofre disso | Feche sessões SSH manuais antigas e abra uma nova antes de testar algo manualmente |
| `docker build` falha com erro de DNS só dentro do build, mas o host resolve DNS normal | BuildKit pode não herdar a config de DNS do host corretamente | Já corrigido via `/etc/docker/daemon.json` com DNS explícito (role `docker` do Ansible) |
| Jenkins morre no boot com erro de Groovy (`unable to resolve class X`) | Script tentando usar uma classe de um **plugin não instalado** (imagem base do Jenkins não vem com nenhum plugin) | Não depender de plugins no `init-admin.groovy` por ora — ver nota no [Dockerfile do Jenkins](../../setup/jenkins/Dockerfile) |
| Depois de um reset de SO, `ssh -i sua-chave` cai em pedido de senha | A chave daquele ambiente específico (Windows *ou* WSL) não foi re-adicionada ao `authorized_keys` da VPS nova | Passo 4 de [SSH First Access](./ssh-first-access.md), para cada ambiente que for usar |

---

## Arquivos de configuração deste cliente (não versionados no Git, ficam só na sua máquina)

- `infra/terraform/clients/mareanalitica/terraform.tfvars` (se/quando for usar Terraform)
- `infra/ansible/group_vars/all.yml`
- `infra/ansible/host_vars/mare.yml`
- `infra/ansible/inventory/hosts.yml` (inventário manual — não usamos o dinâmico via Terraform)
