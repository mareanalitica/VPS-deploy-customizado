# 🚀 Custom VPS Deploy & Base MVP Stack

[![Language: English](https://img.shields.io/badge/Language-English-blue.svg)](./readme.md)
[![Idioma: Português](https://img.shields.io/badge/Idioma-Portugu%C3%Aas-green.svg)](./README_PT.md)
[![Idioma: Español](https://img.shields.io/badge/Idioma-Espa%C3%B1ol-yellow.svg)](./README_ES.md)
[![License: MIT](https://img.shields.io/badge/License-MIT-purple.svg)](./LICENSE)

An open-source, production-ready boilerplate designed to dramatically accelerate the setup, deployment, and infrastructure provisioning of new client MVPs on any VPS (DigitalOcean, Hetzner, AWS EC2).

---

## 🎯 Workflow Overview

1. **Clone Repository:**
   ```bash
   git clone https://github.com/user/vps-deploy-customizado.git
   cd vps-deploy-customizado
   ```
2. **Automated Password & Environment Setup:**
   ```bash
   npm run setup
   ```
   *Automatically generates cryptographically secure 24–32 character secrets for all database/messaging services in `.env` and creates timestamped UUID backups (`env_bkp_YYYY-MM-DD_UUID.env`) if credentials already exist.*

3. **Execution Modes:**
   * **Development (Local):**
     ```bash
     npm run dev:infra
     ```
     *Spins up all services with exposed ports on `localhost` via Docker Compose for easy debugging.*
   * **Production — new client, replicable (recommended):**
      ```bash
      make client-scaffold CLIENT=acme   # copies the Terraform template
      # fill in terraform.tfvars / backend.tf / group_vars/all.yml, then:
      make client-new CLIENT=acme        # terraform apply + ansible-playbook
      ```
      *Provisions a dedicated Hetzner VPS via Terraform and configures it end-to-end via Ansible — same hardening/secrets/deploy steps as below, but consistent across every client and driven from version-controlled config. See the [Client Onboarding Runbook](./docs/infrastructure/client-onboarding-runbook.md).*
   * **Production — manual / single VPS (legacy path, still supported):**
      ```bash
      sudo ./setup/security/harden-vps.sh
      ./setup/init.sh
      npm run deploy:infra
      ```
      *Applies UFW/Fail2ban/DOCKER-USER firewall rules, initializes Docker Swarm, creates Docker Swarm Secrets from `.env`, and issues automatic Let's Encrypt SSL certificates via Traefik. Useful for a single one-off deploy or air-gapped environments where Terraform/Ansible aren't available.*
   * **Database Volumes Backup:**
      ```bash
      npm run backup:volumes
      ```
      *Performs automated compressed backups for MongoDB, PostgreSQL, and Redis with a 7-day retention policy. The Ansible `backup` role additionally schedules this via cron and can push encrypted-in-transit copies to a remote destination via `rclone`.*

---

## 🛠️ Infrastructure Services Stack

* **Reverse Proxy & SSL:** Traefik v2 (Automatic HTTP to HTTPS redirect + Let's Encrypt ACME resolver)
* **Container Management:** Portainer CE
* **CI/CD Pipeline:** Jenkins LTS (Internal local image builds without requiring external Docker Registries)
* **Databases & Caching:** MongoDB, Redis, Postvector (PostgreSQL 16 + `pgvector` extension)
* **Messaging & Object Storage:** RabbitMQ (with Management Plugin), MinIO (S3-compatible)
* **Workflow Automation:** n8n
* **QA & Test Automation:** Headless Chromium service (Remote Debugging Port `9222`)

---

## 📱 Application Stack

* **Backend Core:** NestJS REST API
* **Microservices:** NestJS Payment Service
* **Frontend:** Vite + React + TypeScript PWA (**Mobile-First** & **Offline-First** with background data sync)
* **QA Automation:** Playwright E2E pipeline consuming headless Chromium

---

## 📚 Navigable Documentation Hub (GitHub Ready)

Explore detailed documentation categorized by area and context:

* 💡 **[100 High-Demand Industry Niche Solutions](./docs/niches/niche-solutions.md)** — Blueprints & BaaS workflows (Asaas / Stripe / Split Payments) across 100 commercial verticals.
* 🌐 **[Architecture & Traefik Routing](./docs/infrastructure/architecture.md)** — Ports, Traefik routes, DEV vs PROD mode.
* 🔒 **[Security & VPS Hardening](./docs/infrastructure/security-passwords.md)** — UFW, Fail2ban, and `.env` UUID backup policy.
* 🏗️ **[CI/CD & Jenkins Pipeline](./docs/cicd/jenkins-guide.md)** — Injected `.env` workflows and automatic Docker image pruning.
* 📱 **[Applications Overview (`/apps`)](./docs/applications/overview.md)** — NestJS APIs, Vite PWA, and QA automation setup.
* 📶 **[PWA Offline-First Architecture](./docs/applications/pwa-offline-first.md)** — Offline caching strategies and background sync.
* 🧪 **[QA Automation & Chromium](./docs/applications/qa-automation.md)** — Playwright E2E pipeline consuming headless Chromium.
* 🧠 **[ADR 0001: Docker Swarm over Kubernetes](./docs/adr/0001-why-docker-swarm-over-k8s.md)** — Cost vs complexity trade-offs.
* 🧠 **[ADR 0002: Cloud CI/CD vs. VPS Orchestration Gateway](./docs/adr/0002-cloud-ci-cd-vs-vps-orchestration-gateway.md)** — DX, GitHub Actions costs, and VPS as Orchestration Gateway.
* 🧠 **[ADR 0003: VPS Capacity Limits & Managed Service Segregation](./docs/adr/0003-vps-capacity-limits-and-managed-service-migration-thresholds.md)** — MAU/CCU triggers for migrating to S3, RDS, and Atlas.
* 🧠 **[ADR 0004: Terraform + Ansible Replication](./docs/adr/0004-terraform-ansible-replication.md)** — dedicated-VPS-per-client provisioning model.
* 🧠 **[ADR 0005: Docker Swarm Secrets](./docs/adr/0005-docker-swarm-secrets.md)** — moving infra credentials off plain env vars.
* 🧭 **[Client Onboarding Runbook](./docs/infrastructure/client-onboarding-runbook.md)** — the actual step-by-step for a new client.

---

## 📄 License
Distributed under the MIT License.
