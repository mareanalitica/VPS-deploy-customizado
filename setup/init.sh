#!/usr/bin/env bash
set -e

echo "🚀 [VPS Deploy] Iniciando setup da infraestrutura..."

# 1. Instalar Docker se nao estiver presente
if ! command -v docker &>/dev/null; then
    echo "🐋 Docker nao encontrado. Instalando via get.docker.com..."
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker
    systemctl start docker
    echo "✅ Docker instalado com sucesso."
fi

# 2. Instalar Node.js se nao estiver presente (necessario para manage-env.js)
if ! command -v node &>/dev/null; then
    echo "📦 Node.js nao encontrado. Instalando via NodeSource (v22 LTS)..."
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
    apt-get install -y nodejs
    echo "✅ Node.js instalado com sucesso."
fi

# 3. Gerar / Gerenciar arquivo .env e credenciais
node setup/scripts/manage-env.js

# 4. Inicializar Docker Swarm se nao estiver ativo
if ! docker info 2>/dev/null | grep -q "Swarm: active"; then
    echo "🐋 Inicializando Docker Swarm..."
    docker swarm init || true
else
    echo "✅ Docker Swarm ja esta ativo."
fi

# 5. Criar rede overlay publica
echo "🌐 Criando rede overlay 'public_net'..."
docker network create --driver overlay public_net 2>/dev/null || true

echo ""
echo "🎉 Setup concluido! Para implantar a infra, execute:"
echo "   npm run deploy:infra"
echo ""
