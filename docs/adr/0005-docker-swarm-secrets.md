# ADR 0005: Docker Swarm Secrets for Infrastructure Credentials (Instead of Plain Env Vars)

* **Status:** Accepted
* **Deciders:** System Architect / DevOps Lead
* **Date:** 2026-08-30

---

## Context and Problem Statement

The original `docker-stack.yml` passed every infrastructure credential
(MongoDB, PostgreSQL, Redis, RabbitMQ, MinIO, Jenkins admin) as a plain
Docker Compose/Swarm environment variable, and the API application's
Dockerfile baked its `.env` file directly into the built image via
`COPY .env .env`. Both patterns leave secrets readable by anyone with
`docker inspect`/`docker history` access to the container or image — which,
combined with Jenkins and Portainer both having unrestricted access to the
Docker socket (a separate finding, see the socket-proxy fix in
`docker-stack.yml`), meant a compromise of either admin panel exposed every
credential on the stack, and any image ever built carried a frozen copy of
whatever secrets were valid at build time.

---

## Decision Drivers

* **Least exposure:** a credential should be readable only by the process
  that needs it, not by anything with generic Docker API access.
* **No secrets in image layers:** an image should be safe to build, tag,
  and discard without becoming a permanent record of a point-in-time
  credential.
* **Don't guess at production behavior:** any fix had to be verifiable
  against documented, well-established mechanisms — this ADR's author had
  no live Swarm cluster to test against, so unverifiable changes (e.g.
  overriding an image's entrypoint without knowing its internals) were
  explicitly avoided in favor of leaving a narrower, documented gap.

---

## Considered Options

1. **Keep plain environment variables everywhere (status quo).**
   *Cons:* readable via `docker inspect`/`/proc/<pid>/environ` by anything
   with Docker API access; rejected.

2. **Docker Swarm Secrets via each image's native `_FILE` convention, for
   every service, including best-effort guesses where support isn't
   confirmed (Chosen, with one deliberate exception).**
   *Pros:* mounted read-only at `/run/secrets/*`, never in `docker inspect`
   output, immutable + versionable via secret name suffixes
   (`_v1`, `_v2`, ...) for rotation.
   *Cons:* requires per-image research to confirm `_FILE` support actually
   exists; guessing wrong risks silently breaking a container's startup.

3. **A secrets-management sidecar/vault (e.g. HashiCorp Vault, Doppler).**
   *Pros:* centralized rotation, audit log, dynamic secrets.
   *Cons:* a new stateful service to run, back up, and secure on a
   resource-constrained VPS (see [ADR 0003](./0003-vps-capacity-limits-and-managed-service-migration-thresholds.md));
   disproportionate for the current scale (single VPS per client).

---

## Decision Outcome

**Chosen Option:** **Docker Swarm Secrets**, applied per-service based on
confirmed support, not blanket-applied:

| Service | Mechanism | Confidence |
| :--- | :--- | :--- |
| MongoDB | `MONGO_INITDB_ROOT_PASSWORD_FILE` (native, official image) | High |
| PostgreSQL | `POSTGRES_PASSWORD_FILE` (native, official image) | High |
| RabbitMQ | `RABBITMQ_DEFAULT_PASS_FILE` (native, official image) | High |
| MinIO | `MINIO_ROOT_PASSWORD_FILE` (native, documented for Docker/K8s secrets) | Medium-High |
| Redis | `command: sh -c 'redis-server --requirepass "$(cat /run/secrets/...)"'` (no native `_FILE`, standard documented workaround) | High |
| Jenkins admin password | `init-admin.groovy` reads `/run/secrets/jenkins_admin_password` directly (script we own) | High |
| **n8n encryption key** | **Left as a plain env var** | N/A — deliberately deferred |
| API app secrets (`apps/api-nestjs`) | No longer baked into the image (`COPY .env .env` removed); injected at deploy time | High |

`setup/scripts/deploy.sh` creates the versioned external secrets
(`<name>_v1`) from `.env` before every `docker stack deploy`; rotation
means creating a new versioned secret and pointing the corresponding
`*_SECRET` variable in `.env` at it (secrets are immutable in Swarm by
design — this ADR does not attempt to work around that).

### Why n8n was left out

n8n's official image entrypoint does not have documented, verified support
for reading `N8N_ENCRYPTION_KEY` from a file, and overriding its
`command`/`entrypoint` to inject the value manually — the pattern used
successfully for Redis — could not be validated against a real n8n
container in this environment. Shipping an unverified override risked
silently breaking n8n's startup in production, which is a worse outcome
than leaving one credential (still randomly generated, still never
committed to Git) as a Swarm environment variable. This is tracked as a
follow-up: validate `_FILE` support (or a safe command override) against a
real n8n container before migrating it.

---

## Related Documentation

* 🔒 **[Security & Backup Policy](../infrastructure/security-passwords.md)**
* 🧠 **[ADR 0004: Terraform + Ansible Replication](./0004-terraform-ansible-replication.md)**
* 🏗️ **[CI/CD & Jenkins Pipeline Guide](../cicd/jenkins-guide.md)**
