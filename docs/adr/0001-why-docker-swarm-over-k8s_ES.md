# ADR 0001: Elección de Docker Swarm sobre Kubernetes para Infraestructura MVP de Bajo Coste

[![Language: English](https://img.shields.io/badge/Language-English-blue.svg)](./0001-why-docker-swarm-over-k8s.md)
[![Idioma: Português](https://img.shields.io/badge/Idioma-Portugu%C3%Aas-green.svg)](./0001-why-docker-swarm-over-k8s_PT.md)
[![Idioma: Español](https://img.shields.io/badge/Idioma-Espa%C3%B1ol-yellow.svg)](./0001-why-docker-swarm-over-k8s_ES.md)

* **Estado:** Aceptado (Accepted)
* **Decisores:** Arquitecto de Sistemas / Líder de Ingeniería
* **Fecha:** 2026-08-05

---

## Contexto y Declaración del Problema

Al desplegar nuevos MVPs de clientes, las startups y empresas en fase inicial requieren una pila de infraestructura económica, de alta disponibilidad y de bajo mantenimiento. Gestionar clusters completos de Kubernetes (EKS, GKE, AKS) añade una sobrecarga operativa significativa, controladores de ingress complejos y costes mensuales base elevados (mínimo de ~$100+/mes solo para el plano de control del cluster).

El objetivo principal es proporcionar un pipeline de despliegue con un solo comando en un VPS de bajo coste ($5–$20/mes) con SSL automatizado, orquestación de contenedores, bases de datos, mensajería, CI/CD y aplicaciones móviles orientadas a offline-first.

---

## Factores Decisivos

* **Coste de Infraestructura:** Debe ejecutarse en un único VPS de $5–$20/mes (DigitalOcean, Hetzner, AWS EC2).
* **Simplicidad Operativa:** Cero ingenieros DevOps dedicados a Kubernetes requeridos para el mantenimiento.
* **Onboarding Rápido:** Los desarrolladores deben clonar el repositorio, ejecutar el script de configuración y desplegar en minutos.
* **Ingress y SSL Integrados Nativamente:** Integración con Traefik para la emisión y renovación automática de certificados Let's Encrypt.

---

## Opciones Consideradas

1. **Kubernetes (k8s / k3s / minikube)**
2. **Docker Swarm + Traefik**
3. **Instancia Única Docker Compose Standalone**

---

## Resultado de la Decisión

**Opción Elegida:** **Docker Swarm + Traefik**

### Consecuencias Positivas
* **Bajo Coste:** Funciona de manera eficiente en instancias VPS mononodo o multinodo desde 2GB de RAM.
* **Orquestación Nativa:** Rolling updates nativos (`docker service update`), comprobaciones de salud y redes overlay.
* **Bajo Mantenimiento:** Cero actualizaciones de plano de control de Kubernetes o gestión de `etcd` requeridas.
* **Experiencia de Desarrollo Fluida (DX):** Sintaxis estándar `docker-compose.yml` / `docker-stack.yml`.

### Consecuencias Negativas / Mitigación
* **Escala del Ecosistema:** Menor ecosistema de plugins en comparación con charts de Helm de Kubernetes.
  * *Mitigación:* Pilas preconfiguradas para Jenkins, Portainer, Mongo, Redis, RabbitMQ, MinIO, n8n y Postvector.
