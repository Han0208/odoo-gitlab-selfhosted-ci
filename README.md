# Odoo GitLab Self-Hosted CI

Plantilla reutilizable para automatizar el CI/CD de proyectos Odoo usando un
GitLab self-hosted (Docker) como único servidor: el mismo host que corre
GitLab también aloja los Runners y las instancias de Odoo que el propio
pipeline levanta.

## Para quién es esto

Pensado para empresas, startups o consultoras que manejan proyectos Odoo y
quieren su propio CI/CD sin depender de GitLab.com, SaaS de terceros ni
infraestructura en la nube — todo corre en un servidor privado bajo su
control.

## Objetivo

Servir de guía paso a paso, reproducible, para montar en un servidor privado
un flujo completo:

> push a una rama → build de la imagen Odoo → tests → deploy automático de
> un ambiente Odoo aislado por rama → cleanup al cerrar la rama/MR

La configuración (dominios, credenciales, versión de Odoo) vive en variables
de entorno / archivos `.env.example`, para que cada quien lo adapte a su
propio servidor sin tocar el código del pipeline.

## Arquitectura (resumen)

- **GitLab CE** (Docker) — repos, CI/CD, Container Registry integrado
- **GitLab Runner** (executor Docker) — ejecuta los pipelines
- **Traefik** — reverse proxy con auto-discovery, enruta cada ambiente Odoo
  a su propio subdominio sin tocar config manualmente
- **Instancias Odoo** — levantadas dinámicamente por el pipeline, cada una
  con su propio Postgres

## Estado del proyecto

🚧 En construcción — documentado paso a paso a medida que se avanza.

## Roadmap

- [x] Provisionar el servidor (Docker, firewall) — ver
      [docs/01-provision-server.md](./docs/01-provision-server.md)
- [ ] Levantar GitLab CE — ver [docs/02-gitlab-ce.md](./docs/02-gitlab-ce.md)
      (incluye montar Traefik como ingress desde este paso)
- [ ] Registrar Runner(s)
- [ ] Imagen base de Odoo + docker-compose (Odoo + Postgres)
- [ ] Pipeline: build + test
- [ ] Deploy dinámico por rama con Traefik
- [ ] Backups y persistencia de datos
- [ ] Cleanup automático de ambientes efímeros
- [ ] Configuración por `.env` (sin datos hardcodeados) para que cualquiera
      lo adapte a su propio dominio/servidor
- [ ] Guía de "primeros pasos" para levantar todo desde cero en un servidor
      nuevo
- [x] Licencia open source (MIT)

## Estructura del repo

```
/infra/gitlab/          docker-compose de GitLab CE + Runner
/infra/traefik/         docker-compose + config de Traefik
/templates/odoo/        Dockerfile base de Odoo
/examples/demo-project/ proyecto Odoo de ejemplo con .gitlab-ci.yml
/scripts/               provisioning, backup, restore
/docs/                  guías paso a paso
```

## Licencia

[MIT](./LICENSE) — Hanzel Mesa. Libre para usar, forkear y modificar; solo
se pide mantener el aviso de copyright.
