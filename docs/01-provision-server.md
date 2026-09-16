# Paso 1 — Provisionar el servidor

Este paso prepara un servidor Ubuntu 24.04 limpio con lo mínimo que
necesita el resto del proyecto: Docker y el firewall. Todavía no se instala
GitLab ni nada de Odoo — eso viene en los pasos siguientes.

## Requisitos previos

- Un servidor con Ubuntu 24.04, acceso por SSH y un usuario con `sudo`.
- Puerto 22 abierto para poder entrar por SSH (se preserva durante todo el
  proceso, no se toca).

## Pasos

1. Clona este repositorio directamente en el servidor:

   ```bash
   git clone <url-del-repo> odoo-gitlab-selfhosted-ci
   cd odoo-gitlab-selfhosted-ci
   ```

2. Copia la plantilla de variables de entorno y ajústala si lo necesitas:

   ```bash
   cp .env.example .env
   ```

   Este `.env` de la raíz solo trae variables de alcance servidor, las que
   usan los scripts en `/scripts` antes de que exista ningún stack de
   Docker Compose: `GITLAB_SSH_PORT` (puerto que usará más adelante el
   contenedor de GitLab para git clone/push por SSH) y `EDGE_NETWORK`
   (nombre de la red Docker compartida que crearás en el siguiente paso).
   Los defaults funcionan para la mayoría de los casos — solo cambia
   `GITLAB_SSH_PORT` si ya tienes algo escuchando en ese puerto. Cada stack
   (Traefik, GitLab, ...) trae además su propio `.env.example` junto a su
   `docker-compose.yml`, con la configuración que le es propia.

3. Ejecuta el script de provisioning:

   ```bash
   sudo ./scripts/provision-server.sh
   ```

   Esto hace dos cosas:

   - Instala Docker Engine y el plugin de Docker Compose desde el repositorio
     oficial de Docker (no el paquete `docker.io` de Ubuntu, que suele venir
     desactualizado).
   - Configura `ufw` con política de "denegar todo por defecto" y abre solo
     los puertos necesarios: 22 (SSH, vía el perfil `OpenSSH`), 80 y 443
     (para Traefik) y el puerto de `GITLAB_SSH_PORT` definido en tu `.env`.

4. Cierra la sesión SSH y vuelve a entrar, para que el usuario quede
   aplicado al grupo `docker` (así no necesitas escribir `sudo docker` en
   cada comando).

5. Verifica que todo quedó bien:

   ```bash
   docker run hello-world
   sudo ufw status verbose
   ```

## Por qué estas decisiones

- **ufw en vez de iptables directo**: reglas más simples y legibles para
  cualquiera que reutilice este repo, sin sacrificar lo que necesitamos
  (denegar por defecto + whitelist de puertos).
- **Puerto SSH separado para GitLab (`GITLAB_SSH_PORT`)**: el puerto 22 del
  host se usa para administrar el servidor mismo. GitLab, cuando lo
  instalemos en el siguiente paso, necesita su propio puerto SSH para que
  los desarrolladores hagan `git clone`/`push` — no pueden compartir el 22
  porque hay dos servidores SSH distintos (el del sistema y el del
  contenedor de GitLab) escuchando en el mismo host.
- **Todo parametrizado por `.env`**: quien reutilice este repo en su propio
  servidor solo edita `.env`, nunca el script.

## Siguiente paso

[02 — Levantar GitLab CE](./02-gitlab-ce.md) *(pendiente)*
