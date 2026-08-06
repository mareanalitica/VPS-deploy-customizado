# 🏗️ Area: CI/CD — Jenkins Guide & Dynamic `.env` Injection

[← Back to Documentation Hub](../README.md)

---

## 🎯 Why Use Jenkins in this Boilerplate?

Portainer CE does not support building Docker images directly from Git repositories via UI without configuring an external Docker Registry (such as Docker Hub or private GHCR).

**Jenkins** is included to streamline this pipeline: it builds Docker images locally on the VPS host and updates Docker Swarm services without external registry dependencies.

---

## 🔑 Automated Jenkins Admin Setup (`init-admin.groovy`)

Jenkins initialization is automated via `setup/jenkins/init-admin.groovy`. Upon container startup:
1. Reads `JENKINS_ADMIN_ID` (default: `admin`) and `JENKINS_ADMIN_PASSWORD`.
2. Configures `HudsonPrivateSecurityRealm` and sets `FullControlOnceLoggedInAuthorizationStrategy`.
3. Skips re-configuration safely if security is already configured.

---

## 🔑 Dynamic `.env` Generation & Injection

Each client project maintains its environment configuration template in `setup/docker/` and application `.env` files.

During the build pipeline execution, Jenkins runs:

```groovy
sh "node /opt/vps-deploy/setup/scripts/manage-env.js /opt/vps-deploy/setup/env/apps/${APP_NAME}.env /opt/vps-deploy/setup/env/apps/${APP_NAME}.env.example"
```

1. **Populates empty application secrets** (such as `JWT_SECRET`, `DB_PASSWORD`, `API_KEY`).
2. **Generates timestamped backups** if credentials already existed.
3. **Injects the generated `.env` file** into the build workspace prior to `docker build`.

---

## 🧹 Automated Docker Image Pruning (`docker image prune`)

To prevent recurring builds from exhausting VPS disk storage with orphan images (`dangling images`), the Jenkinsfile template enforces post-build cleanup:

```groovy
post {
    always {
        echo "🧹 Pruning unused Docker images..."
        sh "docker image prune -f --filter 'until=24h'"
    }
}
```

This guarantees intermediate build layers are automatically destroyed without impacting running containers.

