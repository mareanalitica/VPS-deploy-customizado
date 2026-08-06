#!/usr/bin/env bash
set -e

DEPLOY_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BACKUP_DIR="${DEPLOY_ROOT}/setup/backups/volumes"
DATE=$(date +%Y-%m-%d_%H%M%S)
BACKUP_PATH="${BACKUP_DIR}/${DATE}"

if [ ! -f "${DEPLOY_ROOT}/.env" ]; then
    echo "❌ .env nao encontrado em: ${DEPLOY_ROOT}/.env"
    exit 1
fi

set -a
. "${DEPLOY_ROOT}/.env"
set +a

mkdir -p "${BACKUP_PATH}"

echo "📦 Iniciando backup dos volumes de dados..."

MONGO_CONTAINER=$(docker ps -q -f name=infra_mongodb | head -1)
if [ -n "$MONGO_CONTAINER" ]; then
    echo "  → MongoDB..."
    docker exec "$MONGO_CONTAINER" mongodump --archive --gzip \
        -u "${MONGO_INITDB_ROOT_USERNAME:-root}" \
        -p "${MONGO_INITDB_ROOT_PASSWORD}" \
        --authenticationDatabase admin \
        > "${BACKUP_PATH}/mongodb.gz" 2>/dev/null
fi

PG_CONTAINER=$(docker ps -q -f name=infra_postvector | head -1)
if [ -n "$PG_CONTAINER" ]; then
    echo "  → PostgreSQL..."
    docker exec "$PG_CONTAINER" pg_dumpall \
        -U "${POSTGRES_USER:-postgres}" \
        | gzip > "${BACKUP_PATH}/postgresql.gz"
fi

REDIS_CONTAINER=$(docker ps -q -f name=infra_redis | head -1)
if [ -n "$REDIS_CONTAINER" ]; then
    echo "  → Redis..."
    docker exec "$REDIS_CONTAINER" redis-cli \
        -a "${REDIS_PASSWORD}" --no-auth-warning BGSAVE
    sleep 2
    docker cp "${REDIS_CONTAINER}:/data/dump.rdb" "${BACKUP_PATH}/redis.rdb" 2>/dev/null || true
fi

find "${BACKUP_DIR}" -maxdepth 1 -type d -mtime +7 -exec rm -rf {} \; 2>/dev/null || true

echo "✅ Backup concluido em: ${BACKUP_PATH}"
ls -lh "${BACKUP_PATH}/"
