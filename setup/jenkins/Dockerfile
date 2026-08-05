ARG JENKINS_BASE_IMAGE=jenkins/jenkins:lts-jdk17
FROM ${JENKINS_BASE_IMAGE}

# Docker CLI (sem daemon) para os estagios de build/deploy do Jenkinsfile.
# O daemon e' acessado via docker-socket-proxy (DOCKER_HOST), nao via socket montado
# diretamente neste container - por isso nao precisamos rodar como root nem
# adicionar o usuario 'jenkins' ao grupo 'docker' do host.
COPY --from=docker:27-cli /usr/local/bin/docker /usr/local/bin/docker

USER jenkins

# NOTA (revertido de proposito): tentamos instalar matrix-auth +
# workflow-aggregator + git aqui via jenkins-plugin-cli para reforcar a
# seguranca (matrix auth em vez de FullControlOnceLoggedIn) e habilitar
# "pipeline { ... }" no Jenkinsfile.template. Na pratica, isso se mostrou
# um bloqueio real em producao (updates.jenkins.io falhando resolucao de
# DNS de dentro do build do BuildKit, de forma persistente, nao
# transitoria). Simplificado por ora: Jenkins sobe sem plugin nenhum (nucleo
# puro), init-admin.groovy usa a estrategia core-only. Instalar plugins
# (via UI do Jenkins ou revisitando este Dockerfile com calma) fica como
# proximo passo separado, nao bloqueando o essencial.
