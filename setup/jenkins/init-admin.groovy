import jenkins.model.*
import hudson.security.*

def env = System.getenv()
def adminUser = env['JENKINS_ADMIN_ID'] ?: 'admin'
def adminPass = env['JENKINS_ADMIN_PASSWORD']

if (!adminPass) {
    println "[init-admin] JENKINS_ADMIN_PASSWORD nao definida, pulando configuracao."
    return
}

def instance = Jenkins.getInstance()

if (!(instance.getSecurityRealm() instanceof HudsonPrivateSecurityRealm)) {
    def realm = new HudsonPrivateSecurityRealm(false)
    realm.createAccount(adminUser, adminPass)
    instance.setSecurityRealm(realm)

    def strategy = new FullControlOnceLoggedInAuthorizationStrategy()
    strategy.setAllowAnonymousRead(false)
    instance.setAuthorizationStrategy(strategy)
    instance.save()

    println "[init-admin] Admin '${adminUser}' configurado com sucesso."
} else {
    println "[init-admin] Seguranca ja configurada, pulando."
}
