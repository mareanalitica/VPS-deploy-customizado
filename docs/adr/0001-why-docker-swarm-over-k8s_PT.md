# ADR 0001: Escolha do Docker Swarm em vez de Kubernetes para Infraestrutura MVP de Baixo Custo

[![Language: English](https://img.shields.io/badge/Language-English-blue.svg)](./0001-why-docker-swarm-over-k8s.md)
[![Idioma: Português](https://img.shields.io/badge/Idioma-Portugu%C3%Aas-green.svg)](./0001-why-docker-swarm-over-k8s_PT.md)
[![Idioma: Español](https://img.shields.io/badge/Idioma-Espa%C3%B1ol-yellow.svg)](./0001-why-docker-swarm-over-k8s_ES.md)

* **Status:** Aceito (Accepted)
* **Decisores:** Arquiteto de Sistemas / Liderança de Engenharia
* **Data:** 2026-08-05

---

## Contexto e Declaração do Problema

Ao realizar o deploy de novos MVPs de clientes, startups e empresas no estágio inicial exigem uma stack de infraestrutura econômica, de alta disponibilidade e de baixa manutenção. Gerenciar clusters Kubernetes completos (EKS, GKE, AKS) adiciona um overhead operacional significativo, controladores de ingress complexos e custos mensais base elevados (mínimo de ~$100+/mês apenas para o control plane do cluster).

O objetivo principal é fornecer um pipeline de deploy com comando único em uma VPS de baixo custo ($5–$20/mês) com SSL automatizado, orquestração de contêineres, bancos de dados, mensageria, CI/CD e aplicações mobile com suporte a offline-first.

---

## Fatores Decisivos

* **Custo de Infraestrutura:** Deve rodar em uma única VPS de $5–$20/mês (DigitalOcean, Hetzner, AWS EC2).
* **Simplicidade Operacional:** Zero engenheiros DevOps dedicados a Kubernetes necessários para manutenção.
* **Onboarding Rápido:** Desenvolvedores devem clonar o repositório, executar o script de setup e fazer o deploy em minutos.
* **Ingress & SSL Integrados Nativamente:** Integração com Traefik para emissão e renovação automática de certificados Let's Encrypt.

---

## Opções Consideradas

1. **Kubernetes (k8s / k3s / minikube)**
2. **Docker Swarm + Traefik**
3. **Instância Única Docker Compose Standalone**

---

## Resultado da Decisão

**Opção Escolhida:** **Docker Swarm + Traefik**

### Consequências Positivas
* **Baixo Custo:** Opera de forma eficiente em instâncias VPS single-node ou multi-node a partir de 2GB de RAM.
* **Orquestração Nativa:** Rolling updates nativos (`docker service update`), health checks e redes overlay.
* **Baixa Manutenção:** Zero upgrades de control plane Kubernetes ou gerenciamento de `etcd` necessários.
* **Experiência de Desenvolvimento Fluida (DX):** Sintaxe padrão `docker-compose.yml` / `docker-stack.yml`.

### Consequências Negativas / Mitigação
* **Escala do Ecossistema:** Menor ecossistema de plugins se comparado a charts Helm do Kubernetes.
  * *Mitigação:* Stacks pré-configuradas para Jenkins, Portainer, Mongo, Redis, RabbitMQ, MinIO, n8n e Postvector.
