#!/usr/bin/env bash
set -e

if [ ! -f .env ]; then
    echo "❌ Arquivo .env nao encontrado. Execute 'npm run setup' primeiro."
    exit 1
fi

set -a
. ./.env
set +a

echo "🌐 Criando rede overlay 'public_net'..."
docker network create --driver overlay public_net 2>/dev/null || true

echo "🚀 Realizando deploy da stack de infraestrutura..."
docker stack deploy -c setup/docker/docker-stack.yml infra

echo "✅ Stack implantada. Verifique com: docker service ls"
