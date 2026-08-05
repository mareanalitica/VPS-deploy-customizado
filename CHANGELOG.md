# Changelog — VPS Deploy Customizado

## O que é

Boilerplate open-source para provisionar, configurar e deployar infraestrutura
completa numa VPS barata ($5–20/mês) usando Docker Swarm. Pensado para
agências/consultorias que precisam replicar a mesma stack para cada novo cliente
sem passos manuais — um `make client-new CLIENT=acme` cria a VPS, configura tudo
e sobe os serviços.

---

## Stack de infraestrutura (docker-stack.yml)

Serviços que sobem pra todo cliente:

- **Traefik v3.6** — proxy reverso com SSL automático (Let's Encrypt ACME), redirect HTTP→HTTPS, Swarm Provider, portas em `mode: host` para preservar IP real do cliente
- **Portainer CE** — gestão de containers via UI web
- **Jenkins LTS** — CI/CD local com Docker CLI embutido na imagem, sem root, comunicação via docker-socket-proxy
- **PostgreSQL 16 + pgvector** — banco principal com extensão vetorial
- **MongoDB 7** — banco de documentos
- **Redis 7** — cache e filas
- **RabbitMQ 3** — mensageria com plugin de management
- **MinIO** — storage S3-compatível
- **n8n** — automação de workflows
- **Chromium headless** — automação de QA e screenshots
- **docker-socket-proxy** — proxy que filtra endpoints da API Docker (Jenkins e Portainer nunca tocam o socket diretamente)

Cada painel administrativo (Jenkins, Portainer, RabbitMQ, MinIO, Traefik dashboard) é protegido por middleware Traefik de `ipallowlist` configurável via `ADMIN_ALLOWED_CIDRS`.

---

## Stacks de aplicação (opcionais)

Ativadas por toggle no `.env` (`DEPLOY_*_STACK=1`):

### EvoCRM (evocrm-stack.yml)
CRM open-source da Evolution Foundation com 9 serviços:
- **gateway** — nginx reverso que roteia auth/crm/core/processor/bot_runtime
- **auth** — serviço de autenticação (Rails, Sidekiq)
- **crm** — aplicação principal (Rails, Sidekiq)
- **core** — microserviço Go de regras de negócio
- **processor** — processamento de IA (Python/FastAPI)
- **bot_runtime** — runtime de chatbots
- **frontend** — SPA React

Segredos (SECRET_KEY_BASE, JWT, tokens) injetados via Docker Swarm Secrets + wrapper `load-secrets.sh` montado como Swarm Config. Banco dedicado (`evocrm_app`/`evo_community`) com extensões pgvector e pg_stat_statements.

### EvoGo (evogo-stack.yml)
Gateway WhatsApp (Evolution Go) — serviço único com bancos dedicados (`evogo_app`/`evogo_auth`+`evogo_users`).

### Apps (apps-stack.yml)
API NestJS + frontend Vite/React — toggle separado, desativado por padrão.

---

## Automação: Terraform + Ansible

### Terraform (`infra/terraform/`)
- Módulo `vps-client` para Hostinger (extensível para Hetzner/DO)
- Template em `clients/_template/` — `make client-scaffold CLIENT=nome` cria a pasta
- `lifecycle.prevent_destroy` protege contra destruição acidental
- Output de IP alimenta inventário dinâmico do Ansible

### Ansible (`infra/ansible/`)
5 roles idempotentes executadas em ordem:
1. **docker** — instala Docker via apt, inicializa Swarm, cria redes overlay
2. **secrets** — sincroniza `.env` na VPS, gera senhas faltantes via `manage-env.js`
3. **stack_deploy** — roda `deploy.sh` (cria Docker Secrets, provisiona bancos, `docker stack deploy`)
4. **backup** — configura cron de backup criptografado (age) com push para storage remoto
5. **hardening** — UFW, fail2ban, SSH key-only, chain `DOCKER-USER` (por último, de propósito)

Play extra `hostinger_firewall` (connection: local) configura firewall gerenciado via API.

---

## Segurança

- **Docker Swarm Secrets** para MongoDB, PostgreSQL, Redis, RabbitMQ, MinIO, Jenkins, n8n e EvoCRM — senhas nunca visíveis em `docker inspect`
- **docker-socket-proxy** — Jenkins e Portainer acessam Docker via proxy com endpoints filtrados (`CONTAINERS`, `SERVICES`, `TASKS`, `INFO`, `VERSION`, `EVENTS`, `CONFIGS`; `SECRETS`, `EXEC`, `AUTH` bloqueados)
- **IP allowlist** em todos os painéis administrativos via middleware Traefik
- **Portas em mode: host** no Traefik — ingress mesh do Swarm NATeia o IP real; host mode preserva
- **Isolamento por app no banco** — cada app tem role/banco dedicado, nunca o superusuário
- **Backup criptografado** com retenção e push remoto
- **Hardening do host** — UFW, fail2ban, sysctl, SSH key-only, chain DOCKER-USER

---

## Gerenciamento de credenciais (manage-env.js)

- Gera senhas alfanuméricas de 24-32 caracteres para todas as variáveis de segredo
- `CRM_ENCRYPTION_KEY` gera Fernet key (base64 de 32 bytes brutos, compatível com Python cryptography)
- Backup automático do `.env` antes de qualquer alteração (`setup/backups/env_bkp_YYYY-MM-DD_UUID.env`)
- Reconcilia chaves novas do `.env.example` num `.env` existente
- Retenção de no máximo 10 backups por arquivo
- Detecta `.env` ausente com backups existentes e avisa (evita gerar senhas novas que não batem com volumes já inicializados)

---

## Provisionamento de bancos (bootstrap-app-databases.sh)

Script idempotente que cria roles e bancos dedicados:
- `api_nestjs_app` → `app_db` + vhost RabbitMQ `api_nestjs_vhost`
- `evocrm_app` → `evo_community` (+ extensões vector, pg_stat_statements)
- `evogo_app` → `evogo_auth` + `evogo_users`
- `payment_app` → `payment_db` (reservado)

Nunca usa o superusuário para conexão das apps.

---

## Documentação

- **3 idiomas** — EN, PT-BR, ES para README e ADRs
- **ADR 0001** — Docker Swarm vs Kubernetes (custo, simplicidade, trade-offs)
- **ADR 0002** — CI/CD cloud vs orquestração local na VPS
- **ADR 0003** — limites de capacidade da VPS e thresholds de migração para managed services
- **ADR 0004** — Terraform + Ansible para replicação multi-cliente
- **ADR 0005** — Docker Swarm Secrets vs env vars
- **Guia SSH** — primeiro acesso numa VPS nova/resetada
- **Colinha de restart** — reboot vs reset de SO, armadilhas conhecidas

---

## Fluxo de uso

```
# Novo cliente
make client-scaffold CLIENT=acme        # cria pasta Terraform
# preencher terraform.tfvars
make client-new CLIENT=acme             # terraform apply + ansible-playbook

# Desenvolvimento local
npm run setup                           # gera .env com senhas
npm run dev:infra                       # docker compose up (localhost)

# Deploy direto (sem Ansible)
npm run deploy:infra                    # docker stack deploy na VPS
```

---

## Bugs resolvidos em produção

Problemas encontrados e corrigidos durante deploy real na VPS do cliente `mare` (76.13.173.147):

| Problema | Causa raiz | Fix |
|----------|-----------|-----|
| Traefik não lia labels de nenhum container | API Docker v1.24 hardcoded no Traefik v2, engine rejeitava | Migrar para Traefik v3.6 (negociação automática de API) |
| `providers.docker.swarmMode` não existe no v3 | API removida no Traefik v3 | Migrar para `providers.swarm` (Swarm Provider dedicado) |
| Middleware admin-allowlist sumia ao reiniciar | Swarm Provider descarta labels quando `port` está ausente | Adicionar `loadbalancer.server.port` em todo serviço com labels |
| Painéis retornando 403 com IP correto | Ingress mesh NAT mascara IP real (Traefik vê 10.0.0.x) | Publicar portas em `mode: host` |
| Jenkins crash loop a cada ~3 min | Healthcheck usava `wget` (não existe na imagem Debian slim) | Trocar para `curl -fsS` |
| Portainer crash loop | Healthcheck usava `wget`/`/healthcheck` (imagem scratch-like) | `disable: true` no healthcheck |
| Portainer 403 no docker-socket-proxy | Endpoint `/info` não habilitado no proxy | Adicionar `INFO=1`, `VERSION=1`, `EVENTS=1`, `CONFIGS=1` |
| `docker stack deploy` perdia env vars | `docker stack deploy` não lê `.env` (só `docker compose` faz) | Sempre usar `deploy.sh` que faz `source .env` antes |
| EvoCRM `secret_key_base` missing | Entrypoint da imagem roda `db:prepare` antes do wrapper de secrets | Override de `entrypoint:` no compose para `load-secrets.sh` rodar primeiro |
| RabbitMQ vhost não criado em stack nova | `add_vhost` falhava silenciosamente (2>/dev/null engolia erro) | Checar explicitamente com `list_vhosts` antes de criar |
| `CRM_ENCRYPTION_KEY` inválida | `generateSecurePassword()` removia caracteres base64 | `generateFernetKey()` com `crypto.randomBytes(32).toString('base64')` |
| pg_stat_statements faltando | Migration do evo-auth-service exige a extensão | Criar extensão no bootstrap via superusuário |
| asyncpg rejeitava `sslmode=disable` | asyncpg não aceita `sslmode` como kwarg (é sintaxe libpq) | Remover `?sslmode=disable` da connection string |

---

## Estrutura de diretórios

```
.
├── apps/                          # Código-fonte das aplicações
│   ├── api-nestjs/                # Backend NestJS
│   ├── web-vite/                  # Frontend React + Vite
│   ├── api-nestjs-payment-service/# Microserviço de pagamentos (reservado)
│   └── qa-test-automation-pipeline/# Testes E2E com Playwright
├── docs/                          # Documentação trilíngue
│   ├── adr/                       # Architecture Decision Records
│   ├── applications/              # Docs das apps
│   ├── infrastructure/            # SSH, restart, segurança
│   └── niches/                    # 100 nichos comerciais documentados
├── infra/
│   ├── ansible/                   # Playbooks + 6 roles idempotentes
│   │   ├── roles/{docker,secrets,stack_deploy,backup,hardening,hostinger_firewall}
│   │   └── inventory/terraform_inventory.py
│   └── terraform/                 # Provisionamento de VPS por cliente
│       ├── modules/vps-client/    # Módulo reutilizável
│       └── clients/{_template,mare}/
├── setup/
│   ├── docker/                    # Compose files (dev + Swarm)
│   │   ├── docker-stack.yml       # Infra base (Traefik, DBs, Jenkins...)
│   │   ├── evocrm-stack.yml       # Stack EvoCRM (9 serviços)
│   │   ├── evogo-stack.yml        # Stack EvoGo (WhatsApp gateway)
│   │   ├── apps-stack.yml         # Stack NestJS + Vite
│   │   └── docker-compose.dev.yml # Ambiente local de desenvolvimento
│   ├── jenkins/                   # Dockerfile, Groovy init, Jenkinsfile template
│   ├── scripts/                   # deploy.sh, manage-env.js, backup, bootstrap
│   └── security/                  # harden-vps.sh
├── Makefile                       # Atalhos: client-scaffold/plan/new/configure/destroy
├── package.json                   # npm scripts: setup, dev:infra, deploy:infra, backup
└── .env.example                   # Template de todas as variáveis + credenciais
```
