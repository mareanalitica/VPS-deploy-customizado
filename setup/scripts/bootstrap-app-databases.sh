#!/usr/bin/env bash
# Cria banco/role dedicado por app dentro do Postgres/RabbitMQ compartilhados
# desta VPS - nunca usa o superusuario/admin pra conexao das apps. Idempotente:
# seguro rodar de novo (ex: apos "make client-configure" rodar outra vez).
#
# Requer: postvector e rabbitmq ja rodando (chame depois de "docker stack
# deploy"). Senhas vem do .env (geradas por manage-env.js) - so caracteres
# alfanumericos sao suportados aqui (mesma garantia de generateSecurePassword
# em manage-env.js); uma senha com aspas quebraria os comandos SQL abaixo.
set -e

DEPLOY_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

if [ ! -f "${DEPLOY_ROOT}/.env" ]; then
    echo "❌ .env nao encontrado em: ${DEPLOY_ROOT}/.env"
    exit 1
fi

set -a
. "${DEPLOY_ROOT}/.env"
set +a

PG_CONTAINER=""

wait_for_postgres() {
    echo "⏳ Aguardando o container do Postgres ficar pronto..."
    for _ in $(seq 1 30); do
        PG_CONTAINER=$(docker ps -q -f name=infra_postvector | head -1)
        if [ -n "$PG_CONTAINER" ] && docker exec "$PG_CONTAINER" pg_isready -U "${POSTGRES_USER:-postgres}" >/dev/null 2>&1; then
            return 0
        fi
        sleep 2
    done
    echo "❌ Postgres nao ficou pronto a tempo."
    exit 1
}

psql_exec() {
    docker exec -i "$PG_CONTAINER" psql -v ON_ERROR_STOP=1 -U "${POSTGRES_USER:-postgres}" "$@"
}

ensure_role() {
    local role="$1" password="$2"
    if [ -z "$password" ]; then
        echo "   ⚠️  Sem senha para o role '$role' - pulando (variavel ausente no .env?)."
        return 1
    fi
    local exists
    exists=$(psql_exec -tAc "SELECT 1 FROM pg_roles WHERE rolname = '${role}'")
    if [ "$exists" = "1" ]; then
        # Idempotente tambem pra rotacao: sempre reafirma a senha atual do .env.
        psql_exec -c "ALTER ROLE ${role} WITH LOGIN PASSWORD '${password}'"
        echo "   → Role '${role}' ja existia, senha sincronizada."
    else
        psql_exec -c "CREATE ROLE ${role} WITH LOGIN PASSWORD '${password}'"
        echo "   ✅ Role '${role}' criado."
    fi
}

ensure_database() {
    local db="$1" owner="$2"
    local exists
    exists=$(psql_exec -tAc "SELECT 1 FROM pg_database WHERE datname = '${db}'")
    if [ "$exists" = "1" ]; then
        echo "   → Banco '${db}' ja existe."
    else
        psql_exec -c "CREATE DATABASE ${db} OWNER ${owner}"
        echo "   ✅ Banco '${db}' criado (owner: ${owner})."
    fi
}

echo "🗄️  Provisionando bancos/roles dedicados por app no Postgres..."
wait_for_postgres

# api-nestjs: reaproveita o banco "app_db" ja criado pelo POSTGRES_DB do
# postvector (dono original: superusuario), transfere para um role dedicado.
if ensure_role "api_nestjs_app" "${API_NESTJS_DB_PASSWORD}"; then
    psql_exec -c "ALTER DATABASE ${POSTGRES_DB:-app_db} OWNER TO api_nestjs_app"
    psql_exec -d "${POSTGRES_DB:-app_db}" -c "GRANT ALL ON SCHEMA public TO api_nestjs_app"
fi

# EvoCRM: banco proprio + extensoes exigidas pela app. "vector" (busca
# semantica) e "pg_stat_statements" (usada pela migration InitSchema do
# evo-auth-service) so podem ser criadas por um superusuario - por isso
# rodam aqui via psql_exec (conectado como POSTGRES_USER), nao dentro da
# migration da app (que roda como o role dedicado "evocrm_app", sem
# privilegio pra CREATE EXTENSION). pg_stat_statements tambem exige estar
# em shared_preload_libraries do Postgres (ver command: no docker-stack.yml).
if ensure_role "evocrm_app" "${EVOCRM_DB_PASSWORD}"; then
    ensure_database "evo_community" "evocrm_app"
    psql_exec -d evo_community -c "CREATE EXTENSION IF NOT EXISTS vector"
    psql_exec -d evo_community -c "CREATE EXTENSION IF NOT EXISTS pg_stat_statements"
fi

# EvoGo (Evolution Go): duas bases proprias exigidas pela app - auth e users.
if ensure_role "evogo_app" "${EVOGO_DB_PASSWORD}"; then
    ensure_database "evogo_auth" "evogo_app"
    ensure_database "evogo_users" "evogo_app"
fi

# Reservado: api-nestjs-payment-service ainda sem codigo implementado - so
# o banco/role ja ficam preparados pra quando a app existir de verdade.
if ensure_role "payment_app" "${PAYMENT_DB_PASSWORD}"; then
    ensure_database "payment_db" "payment_app"
fi

echo "✅ Bancos/roles do Postgres provisionados."

wait_for_rabbitmq() {
    echo "⏳ Aguardando o RabbitMQ ficar pronto..."
    for _ in $(seq 1 30); do
        if docker exec "$RABBITMQ_CONTAINER" rabbitmqctl status >/dev/null 2>&1; then
            return 0
        fi
        sleep 2
    done
    echo "❌ RabbitMQ nao ficou pronto a tempo."
    exit 1
}

echo "🐰 Provisionando vhost dedicado do RabbitMQ para api-nestjs..."
RABBITMQ_CONTAINER=$(docker ps -q -f name=infra_rabbitmq | head -1)
if [ -n "$RABBITMQ_CONTAINER" ] && [ -n "${API_NESTJS_RABBITMQ_PASSWORD}" ]; then
    wait_for_rabbitmq
    # "2>/dev/null || true" antigo engolia QUALQUER falha do add_vhost (nao so
    # "ja existe") - numa stack recem-criada, rabbitmqctl podia ainda nao estar
    # pronto (Mnesia/Erlang node bootando) mesmo com o container ja "Running"
    # no "docker ps", entao o vhost as vezes nunca era criado de verdade e o
    # "set_permissions" adiante falhava com "Virtual host ... does not exist".
    # Checar explicitamente em vez de silenciar erro evita esse falso-positivo.
    if ! docker exec "$RABBITMQ_CONTAINER" rabbitmqctl list_vhosts | grep -qx "api_nestjs_vhost"; then
        docker exec "$RABBITMQ_CONTAINER" rabbitmqctl add_vhost api_nestjs_vhost
    fi
    docker exec "$RABBITMQ_CONTAINER" rabbitmqctl add_user api_nestjs_app "${API_NESTJS_RABBITMQ_PASSWORD}" 2>/dev/null \
        || docker exec "$RABBITMQ_CONTAINER" rabbitmqctl change_password api_nestjs_app "${API_NESTJS_RABBITMQ_PASSWORD}"
    docker exec "$RABBITMQ_CONTAINER" rabbitmqctl set_permissions -p api_nestjs_vhost api_nestjs_app ".*" ".*" ".*"
    echo "✅ Vhost 'api_nestjs_vhost' e usuario 'api_nestjs_app' provisionados no RabbitMQ."
else
    echo "ℹ️  RabbitMQ nao encontrado rodando ou API_NESTJS_RABBITMQ_PASSWORD vazio - pulando."
fi
