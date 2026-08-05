# 🏗️ Area: CI/CD — Jenkins Guide & Dynamic `.env` Injection

[← Back to Documentation Hub](../README.md)

---

## 🎯 Why Use Jenkins in this Boilerplate?

Portainer CE does not support building Docker images directly from Git repositories via UI without configuring an external Docker Registry (such as Docker Hub or private GHCR).

**Jenkins** is included to streamline this pipeline: it builds Docker images locally on the VPS host and updates Docker Swarm services without external registry dependencies.

---

## 🔑 Automated Jenkins Admin Setup (`init-admin.groovy`)

Jenkins initialization is automated via `setup/jenkins/init-admin.groovy`. Upon container startup:
1. Reads `JENKINS_ADMIN_ID` (default: `admin`) and the admin password — preferring the Docker Swarm secret mounted at `/run/secrets/jenkins_admin_password`, falling back to `JENKINS_ADMIN_PASSWORD` for local DEV.
2. Configures `HudsonPrivateSecurityRealm` and sets `GlobalMatrixAuthorizationStrategy`, granting `Jenkins.ADMINISTER` only to the configured admin user. Unlike the previous `FullControlOnceLoggedInAuthorizationStrategy`, any additional user created later has **no** permissions until explicitly granted.
3. Skips re-configuration safely if security is already configured.

Jenkins no longer runs as `root` and no longer mounts `/var/run/docker.sock` directly — it talks to the Docker daemon through `docker-socket-proxy` (`DOCKER_HOST=tcp://docker-proxy:2375`), which exposes a filtered subset of the Docker API (no `SECRETS`, `EXEC`, `PLUGINS`, or `SYSTEM` endpoints). The Jenkins image itself is now built locally from `setup/jenkins/Dockerfile` (base image + Docker CLI only) by `setup/scripts/deploy.sh` before every `docker stack deploy`.

The `jenkins.<DOMAIN_NAME>` route is restricted by the `admin-allowlist` Traefik middleware — set `ADMIN_ALLOWED_CIDRS` in `.env` to your team's real IP(s)/CIDR(s), or the panel stays unreachable (safe default).

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

