import jenkins.model.*
import hudson.security.*

def env = System.getenv()
def adminUser = env['JENKINS_ADMIN_ID'] ?: 'admin'

// Preferir o segredo montado via Docker Swarm secret (/run/secrets/...);
// cair para a env var apenas em ambientes sem secrets configurados (ex: DEV local).
def secretFile = new File('/run/secrets/jenkins_admin_password')
def adminPass = secretFile.exists() ? secretFile.text.trim() : env['JENKINS_ADMIN_PASSWORD']

if (!adminPass) {
    println "[init-admin] Nenhuma senha de admin encontrada (secret ou env var), pulando configuracao."
    return
}

def instance = Jenkins.getInstance()

if (!(instance.getSecurityRealm() instanceof HudsonPrivateSecurityRealm)) {
    def realm = new HudsonPrivateSecurityRealm(false)
    realm.createAccount(adminUser, adminPass)
    instance.setSecurityRealm(realm)

    // Revertido de proposito para a estrategia core-only (nao depende do
    // plugin matrix-auth, que causou instabilidade real de build - ver
    // nota em setup/jenkins/Dockerfile). FullControlOnceLoggedIn concede
    // controle total a QUALQUER usuario autenticado, nao so' ao admin -
    // achado de seguranca conhecido, aceito temporariamente. Reforçar para
    // matrix-auth fica como proximo passo separado (instalar o plugin com
    // calma, fora do caminho critico do deploy).
    def strategy = new FullControlOnceLoggedInAuthorizationStrategy()
    strategy.setAllowAnonymousRead(false)
    instance.setAuthorizationStrategy(strategy)
    instance.save()

    println "[init-admin] Admin '${adminUser}' configurado (estrategia core-only, sem plugin matrix-auth)."
} else {
    println "[init-admin] Seguranca ja configurada, pulando."
}
