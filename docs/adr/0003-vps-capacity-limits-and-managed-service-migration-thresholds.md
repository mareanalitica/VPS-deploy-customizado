# ADR 0003: VPS Capacity Thresholds & Gradual Service Migration to Managed Cloud (S3, Managed DBs)

* **Status:** Accepted
* **Deciders:** System Architect / Lead DevOps Engineer / Engineering Manager
* **Date:** 2026-08-06

---

## Context and Problem Statement

Our baseline architecture utilizes a self-hosted Docker Swarm stack running on a single low-cost VPS ($5–$24/month) to serve early-stage client MVPs. As proven in our financial evaluations, running unified services (Traefik, NestJS, MongoDB, Postgres, Redis, MinIO, RabbitMQ, n8n) on a single VPS saves **85% to 96%** in infrastructure costs compared to fully managed SaaS platforms at low traffic volumes (100 MAU).

However, as an application grows in Monthly Active Users (MAU), Concurrent Users (CCU), and data throughput, a single VPS node will eventually encounter hardware bottlenecks:
1. **Memory (RAM) Starvation:** OOM Killer terminating database processes when combined working sets exceed host RAM.
2. **Disk I/O Bottlenecks:** Heavy database writes competing with log files and local object storage reads.
3. **Storage Exhaustion:** User-uploaded media files filling up local NVMe/SSD drives.
4. **High Availability (HA) & Compliance:** Lack of automated multi-region failover, multi-AZ replication, or Point-In-Time-Recovery (PITR).

This ADR establishes concrete, metrics-driven operational thresholds to define **WHEN** and **HOW** to break apart the monolithic VPS stack and migrate specific high-cost or high-risk infrastructure components (Object Storage, PostgreSQL/RDS, MongoDB Atlas) to managed cloud services.

---

## Decision Drivers

* **Unit Economics & Financial Milestones:** Maximizing ROI during bootstrap phases while migrating services only when business revenue justifies higher cloud baseline costs.
* **Resource Saturation Thresholds:** Quantifiable hardware signals (CPU %, RAM %, Disk IOPS latency, Storage fill rate).
* **Workload Scale Metrics:** MAU (Monthly Active Users), CCU (Concurrent Users / Peak Connections), and RPS (Requests Per Second).
* **Operational Risk Management:** Data safety, automated continuous backups, PITR, and SLA guarantees.

---

## Migration Framework: 3-Phase Lifecycle Model

```mermaid
flowchart TD
    subgraph Phase 1: Monolithic VPS [100 - 10,000 MAU]
        VPS1[Single VPS Node - 4GB RAM]
        VPS1 -->|Runs All Containers| C1[Traefik + APIs + Postgres + Mongo + Redis + MinIO]
    end

    subgraph Phase 2: Storage Offload [10,000 - 50,000 MAU]
        VPS2[VPS Node - 4GB to 8GB RAM]
        VPS2 -->|Runs Core Stack| C2[Traefik + APIs + Postgres + Mongo + Redis]
        VPS2 -.->|Offload Media Uploads| R2[Cloudflare R2 / AWS S3]
    end

    subgraph Phase 3: DB Segregation [50,000 - 200,000+ MAU]
        VPS3[VPS Orchestration Node - 8GB RAM]
        VPS3 -->|Runs App Tier| C3[Traefik Ingress + NestJS APIs + Redis Cache]
        VPS3 -.->|Offload Media| R2_3[Cloudflare R2 / AWS S3]
        VPS3 -.->|Managed SQL| RDS[AWS RDS Postgres / Supabase]
        VPS3 -.->|Managed NoSQL| Atlas[MongoDB Atlas M10/M20]
    end

    Phase 1 -->|Storage > 30GB or CCU > 50| Phase 2
    Phase 2 -->|RAM > 85% or DB IOPS Latency > 20ms| Phase 3
```

---

## Detailed Capacity & Metrics Breakdown

### Phase 1: Unified Self-Hosted VPS Stack (Bootstrap & MVP Validation)

* **Target Traffic:** **100 to 10,000 MAU**
* **Concurrent Active Users (CCU):** **1 to 50 concurrent users**
* **Peak Throughput:** **< 50 Requests / Second (RPS)**
* **Database Size Limit:** **< 25 GB total**
* **Object Storage Limit:** **< 20 GB media/assets**

#### Infrastructure Configuration & Cost:
- **Hosting:** 1x VPS Node (2 vCPU, 4GB RAM, 40–80GB SSD).
  - Hetzner CAX11/CX23 (~$5.00/mo) OR DigitalOcean Basic ($24.00/mo) OR AWS EC2 t4g.small ($15.00/mo).
- **Stack:** 100% self-hosted Docker Swarm (Traefik, NestJS, Postgres, Mongo, Redis, MinIO, RabbitMQ, n8n).
- **Total Monthly Cost:** **$5.00 – $24.00 / month**

---

### Phase 2: Hybrid Storage Offload (Growth Phase)

* **Trigger Thresholds (Any of the following):**
  - Local disk storage exceeds **30 GB** (or 70% of local disk capacity).
  - Media file upload/download traffic creates disk IOPS contention with database write queries.
  - Outbound bandwidth usage exceeds free VPS quotas.
* **Target Traffic:** **10,000 to 50,000 MAU**
* **Concurrent Active Users (CCU):** **50 to 250 concurrent users**
* **Peak Throughput:** **50 to 150 Requests / Second (RPS)**

#### Infrastructure Configuration & Cost:
- **Compute & Databases:** 1x VPS Node (2-4 vCPU, 4-8GB RAM) running APIs, MongoDB, Postgres, Redis (~$24.00/mo).
- **Object Storage Migration:** Offload local MinIO to **Cloudflare R2** (Zero egress fees, $0.015/GB-month) or **AWS S3**.
- **Total Monthly Cost:** **$26.00 – $35.00 / month**
  - *Savings vs Managed SaaS:* Still **~80% cheaper** than full cloud SaaS ($180+/mo).

---

### Phase 3: Database Segregation & Managed Services (High-Scale Phase)

* **Trigger Thresholds (Any of the following):**
  - Database RAM working set exceeds available host memory (VPS RAM utilization consistently **> 85%**).
  - Sustained disk write IOPS latency exceeds **20ms**, causing API timeout cascades.
  - Product requirements demand **Point-In-Time-Recovery (PITR)**, automated multi-AZ continuous replication, or strict SLA guarantees (99.99%).
* **Target Traffic:** **50,000 to 200,000+ MAU**
* **Concurrent Active Users (CCU):** **250 to 2,000+ concurrent active users**
* **Peak Throughput:** **> 200 Requests / Second (RPS)**

#### Infrastructure Configuration & Cost:
- **Application & Ingress Tier (VPS):** 1x or 2x VPS Nodes acting as **Orchestration Gateway** (Traefik + NestJS APIs + Redis Cache) (~$24.00 – $48.00/mo).
- **Managed Relational DB:** AWS RDS PostgreSQL `db.t4g.medium` or Supabase Pro (~$30.00 – $60.00/mo).
- **Managed NoSQL DB:** MongoDB Atlas `M10` / `M20` Dedicated Cluster (~$57.00 – $100.00/mo).
- **Managed Object Storage:** Cloudflare R2 / AWS S3 (~$10.00 – $20.00/mo).
- **Total Monthly Cost:** **$121.00 – $228.00 / month**

---

## Financial & Operational Matrix Summary

| Architectural Phase | MAU Range | Concurrent Users (CCU) | Trigger Signal / Constraint | Primary Infrastructure | Monthly Cost Range |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Phase 1: Self-Hosted Monolith** | 100 – 10,000 | 1 – 50 CCU | MVP validation, low storage (<25GB) | 1x VPS (4GB RAM) | **$5 – $24 / mo** |
| **Phase 2: Storage Offload** | 10,000 – 50,000 | 50 – 250 CCU | Storage > 30GB or I/O contention | VPS + Cloudflare R2 / S3 | **$26 – $35 / mo** |
| **Phase 3: DB Segregation** | 50,000 – 200,000+ | 250 – 2,000+ CCU | RAM > 85%, IOPS latency > 20ms, HA SLA | VPS Gateway + AWS RDS + Mongo Atlas + R2 | **$121 – $228 / mo** |

---

## Decision Outcome

**Chosen Strategy:** **Gradual 3-Phase Migration Model**

1. **Start Monolithic (Phase 1):** Deploy the complete stack on a single low-cost VPS ($5–$24/mo) to validate the MVP with maximum financial efficiency (saving up to 96% vs cloud SaaS).
2. **First Offload Target — Media Storage (Phase 2):** When local storage reaches 30 GB or 50+ concurrent users, migrate media assets to Cloudflare R2 / AWS S3. This requires zero code changes due to S3 API compatibility in MinIO.
3. **Second Offload Target — Managed Databases (Phase 3):** When hitting 250+ concurrent users, 50,000+ MAU, or RAM/IOPS saturation (>85%), migrate Postgres to AWS RDS/Supabase and Mongo to Atlas.

---

## Related Documentation

* 🧠 **[ADR 0001: Docker Swarm over Kubernetes](./0001-why-docker-swarm-over-k8s.md)**
* 🧠 **[ADR 0002: Cloud CI/CD vs. VPS Orchestration Gateway](./0002-cloud-ci-cd-vs-vps-orchestration-gateway.md)**
* 🔒 **[Security & Backup Policy](../infrastructure/security-passwords.md)**
