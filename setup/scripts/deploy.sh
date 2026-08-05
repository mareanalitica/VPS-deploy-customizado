#!/usr/bin/env bash
set -e

if [ ! -f .env ]; then
    echo "❌ Arquivo .env nao encontrado. Execute 'npm run setup' primeiro."
    exit 1
fi

set -a
. ./.env
set +a

echo "🌐 Criando redes overlay 'public_net' e 'internal_net'..."
# Criadas fora do lifecycle de qualquer stack especifico (nao "owned" por
# "infra") para que apps-stack.yml/evocrm-stack.yml/evogo-stack.yml
# consigam se conectar a elas como "external: true" sem prefixo de stack.
docker network create --driver overlay public_net 2>/dev/null || true
docker network create --driver overlay --internal --opt encrypted=true internal_net 2>/dev/null || true

echo "🔑 Garantindo Docker Secrets a partir do .env..."
create_secret_if_missing() {
    local name="$1"
    local value="$2"
    if [ -z "$value" ]; then
        echo "   ⚠️  Valor vazio para o secret '$name' - pulando (variavel ausente no .env?)."
        return
    fi
    if docker secret inspect "$name" >/dev/null 2>&1; then
        echo "   → '$name' ja existe, mantendo (secrets do Swarm sao imutaveis)."
    else
        printf '%s' "$value" | docker secret create "$name" -
        echo "   ✅ Secret '$name' criado."
    fi
}

create_secret_if_missing "${MONGO_ROOT_PASSWORD_SECRET:-mongo_root_password_v1}" "$MONGO_INITDB_ROOT_PASSWORD"
create_secret_if_missing "${POSTGRES_PASSWORD_SECRET:-postgres_password_v1}" "$POSTGRES_PASSWORD"
create_secret_if_missing "${REDIS_PASSWORD_SECRET:-redis_password_v1}" "$REDIS_PASSWORD"
create_secret_if_missing "${RABBITMQ_PASS_SECRET:-rabbitmq_pass_v1}" "$RABBITMQ_DEFAULT_PASS"
create_secret_if_missing "${MINIO_ROOT_PASSWORD_SECRET:-minio_root_password_v1}" "$MINIO_ROOT_PASSWORD"
create_secret_if_missing "${JENKINS_ADMIN_PASSWORD_SECRET:-jenkins_admin_password_v1}" "$JENKINS_ADMIN_PASSWORD"

# apps-stack.yml (api-nestjs)
if [ "${DEPLOY_APPS_STACK:-0}" = "1" ]; then
    create_secret_if_missing "${API_NESTJS_DB_PASSWORD_SECRET:-api_nestjs_db_password_v1}" "$API_NESTJS_DB_PASSWORD"
    create_secret_if_missing "${API_NESTJS_RABBITMQ_PASSWORD_SECRET:-api_nestjs_rabbitmq_password_v1}" "$API_NESTJS_RABBITMQ_PASSWORD"
fi

# evocrm-stack.yml
if [ "${DEPLOY_EVOCRM_STACK:-0}" = "1" ]; then
    create_secret_if_missing "${EVOCRM_DB_PASSWORD_SECRET:-evocrm_db_password_v1}" "$EVOCRM_DB_PASSWORD"
    create_secret_if_missing "${CRM_SECRET_KEY_BASE_SECRET:-crm_secret_key_base_v1}" "$CRM_SECRET_KEY_BASE"
    create_secret_if_missing "${CRM_JWT_SECRET_KEY_SECRET:-crm_jwt_secret_key_v1}" "$CRM_JWT_SECRET_KEY"
    create_secret_if_missing "${CRM_DOORKEEPER_JWT_SECRET_KEY_SECRET:-crm_doorkeeper_jwt_secret_key_v1}" "$CRM_DOORKEEPER_JWT_SECRET_KEY"
    create_secret_if_missing "${CRM_ENCRYPTION_KEY_SECRET:-crm_encryption_key_v1}" "$CRM_ENCRYPTION_KEY"
    create_secret_if_missing "${CRM_EVOAI_CRM_API_TOKEN_SECRET:-crm_evoai_crm_api_token_v1}" "$CRM_EVOAI_CRM_API_TOKEN"
    create_secret_if_missing "${CRM_BOT_RUNTIME_SECRET_SECRET:-crm_bot_runtime_secret_v1}" "$CRM_BOT_RUNTIME_SECRET"
fi

# evogo-stack.yml nao usa Docker Secrets (ver nota no proprio arquivo) - so
# precisa de EVOGO_DB_PASSWORD/EVOGO_GLOBAL_API_KEY no .env, nada a criar aqui.

echo "🏗️  Buildando imagem customizada do Jenkins (com Docker CLI, sem root)..."
docker build -t "${JENKINS_IMAGE:-vps-deploy-jenkins:lts-jdk17}" setup/jenkins/

echo "🚀 Realizando deploy da stack de infraestrutura..."
docker stack deploy -c setup/docker/docker-stack.yml infra

if [ "${DEPLOY_APPS_STACK:-0}" = "1" ] || [ "${DEPLOY_EVOCRM_STACK:-0}" = "1" ] || [ "${DEPLOY_EVOGO_STACK:-0}" = "1" ]; then
    echo "🗄️  Provisionando bancos/roles/vhosts dedicados por app..."
    bash setup/scripts/bootstrap-app-databases.sh
fi

if [ "${DEPLOY_APPS_STACK:-0}" = "1" ]; then
    echo "🚀 Deploy da stack de aplicacoes (api-nestjs, web-vite)..."
    docker stack deploy -c setup/docker/apps-stack.yml apps
fi

if [ "${DEPLOY_EVOCRM_STACK:-0}" = "1" ]; then
    echo "🚀 Deploy da stack do EvoCRM..."
    docker stack deploy -c setup/docker/evocrm-stack.yml evocrm
fi

if [ "${DEPLOY_EVOGO_STACK:-0}" = "1" ]; then
    echo "🚀 Deploy da stack do EvoGo..."
    docker stack deploy -c setup/docker/evogo-stack.yml evogo
fi

echo "✅ Stack(s) implantada(s). Verifique com: docker service ls"
echo ""
echo "ℹ️  Para rotacionar uma senha: gere um novo valor, crie um secret com nome"
echo "   versionado novo (ex: mongo_root_password_v2), aponte a variavel"
echo "   *_SECRET correspondente no .env para ele e rode este script novamente."
