#!/bin/sh
# Montado via Swarm Config em todo container evocrm_*. Le os Docker Swarm
# Secrets montados em /run/secrets/*, exporta como env var (unica forma
# generica de injetar segredo numa imagem de terceiros cujo entrypoint nao
# temos como confirmar que suporta convencao "_FILE" nativa - mesmo
# raciocinio ja usado pro Redis em docker-stack.yml), e entao exec o
# comando real da imagem recebido como argumentos.
set -e

export SECRET_KEY_BASE="$(cat /run/secrets/crm_secret_key_base)"
export JWT_SECRET_KEY="$(cat /run/secrets/crm_jwt_secret_key)"
export EVOAI_CRM_API_TOKEN="$(cat /run/secrets/crm_evoai_crm_api_token)"
[ -f /run/secrets/crm_doorkeeper_jwt_secret_key ] && export DOORKEEPER_JWT_SECRET_KEY="$(cat /run/secrets/crm_doorkeeper_jwt_secret_key)"
[ -f /run/secrets/crm_encryption_key ] && export ENCRYPTION_KEY="$(cat /run/secrets/crm_encryption_key)"
[ -f /run/secrets/crm_bot_runtime_secret ] && export BOT_RUNTIME_SECRET="$(cat /run/secrets/crm_bot_runtime_secret)"
[ -f /run/secrets/crm_smtp_password ] && export SMTP_PASSWORD="$(cat /run/secrets/crm_smtp_password)"

export POSTGRES_PASSWORD="$(cat /run/secrets/evocrm_db_password)"
export DB_PASSWORD="$POSTGRES_PASSWORD"
export REDIS_PASSWORD="$(cat /run/secrets/redis_password)"
export REDIS_URL="redis://:${REDIS_PASSWORD}@redis:6379/1"
# SEM "?sslmode=disable": o evocrm_processor usa SQLAlchemy assincrono
# (driver asyncpg) pra rodar as migrations, e asyncpg.connect() nao aceita
# "sslmode" como kwarg (isso e sintaxe libpq/psycopg2, nao asyncpg) - quebra
# com "TypeError: connect() got an unexpected keyword argument 'sslmode'".
# Omitir o parametro basta: sem SSL configurado, ambos os drivers (psycopg2
# via "prefer", asyncpg via default) conectam em texto plano normalmente,
# que e o esperado aqui (internal_net ja e' overlay encrypted=true).
export POSTGRES_CONNECTION_STRING="postgresql://evocrm_app:${POSTGRES_PASSWORD}@postvector:5432/evo_community"

exec "$@"
