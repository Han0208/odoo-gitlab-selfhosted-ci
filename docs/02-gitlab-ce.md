# Paso 2 — Levantar GitLab CE (detrás de Traefik)

Este paso monta dos piezas juntas: **Traefik**, como único punto de entrada
HTTP(S) del servidor, y **GitLab CE**, corriendo detrás de él. Se hacen
juntas porque Traefik necesita ser quien ocupe los puertos 80/443 del host
desde el principio — si GitLab los tomara directamente ahora, tocaría
reconfigurarlo más adelante cuando lleguen los ambientes Odoo, que también
se enrutan por Traefik.

## Requisitos previos

- Paso 1 completado (Docker + firewall).
- Al menos 4 GB de RAM libres en el servidor (8 GB recomendado). GitLab CE
  es pesado; con menos memoria puede quedarse a medias al iniciar.

## Configuración

Edita tu `.env` (no `.env.example`) y completa:

- `BASE_DOMAIN`: si no tienes dominio propio todavía, usa el truco de
  [nip.io](https://nip.io): `<IP-de-tu-servidor>.nip.io` resuelve
  públicamente a esa IP sin configurar DNS. Ejemplo: si tu servidor está en
  `192.168.1.50`, pon `BASE_DOMAIN=192.168.1.50.nip.io`.
- El resto de variables (`EDGE_NETWORK`, `TRAEFIK_VERSION`, `GITLAB_VERSION`,
  `GITLAB_SSH_PORT`) ya tienen defaults razonables — solo revísalas.
- `ACME_EMAIL` no aplica todavía (es para cuando actives HTTPS con un
  dominio real, ver más abajo).

## Pasos

1. Crea la red compartida (una sola vez por servidor):

   ```bash
   ./scripts/create-network.sh
   ```

2. Levanta Traefik:

   ```bash
   cd infra/traefik
   docker compose up -d
   ```

3. Levanta GitLab (la primera vez tarda varios minutos en inicializar —
   sigue los logs para saber cuándo terminó):

   ```bash
   cd ../gitlab
   docker compose up -d
   docker compose logs -f gitlab
   ```

   Cuando veas logs relativamente tranquilos (sin reconfigures corriendo en
   bucle) y `docker compose ps` muestre el contenedor como `healthy`, ya
   puedes entrar.

4. Entra a `http://gitlab.<BASE_DOMAIN>` desde el navegador. La contraseña
   inicial del usuario `root` queda en:

   ```bash
   cat infra/gitlab/data/config/initial_root_password
   ```

   Ese archivo se borra solo a las 24 horas — cambia la contraseña de
   `root` apenas entres.

## Cuando tengas un dominio real (activar HTTPS)

1. Apunta el DNS de tu dominio al servidor y actualiza `BASE_DOMAIN` en
   `.env` con ese dominio real.
2. Crea el archivo donde Traefik guarda los certificados, con permisos
   `600` (Let's Encrypt lo exige):

   ```bash
   cd infra/traefik
   touch data/acme.json
   chmod 600 data/acme.json
   ```

3. Levanta Traefik incluyendo el override de HTTPS:

   ```bash
   docker compose -f docker-compose.yml -f docker-compose.https.yml up -d
   ```

4. Actualiza `infra/gitlab/docker-compose.yml`: cambia `external_url` a
   `https://gitlab.${BASE_DOMAIN}` y agrega las labels de Traefik para el
   entrypoint `websecure` con `tls.certresolver=letsencrypt`. Luego
   `docker compose up -d` de nuevo para aplicar.

## Por qué estas decisiones

- **Traefik desde ya, aunque hoy no haga falta HTTPS**: evita un cambio de
  arquitectura más adelante — cuando el pipeline empiece a crear ambientes
  Odoo por rama, todos comparten el mismo Traefik y la misma red `edge`,
  cada uno solo agregando sus propias labels.
- **Red Docker externa (`edge`) en vez de una red por stack**: Traefik,
  GitLab y los futuros ambientes Odoo viven en `docker-compose.yml`
  distintos (stacks independientes). Para que Traefik pueda enrutar hacia
  todos, todos deben compartir una red — por eso se crea aparte con
  `scripts/create-network.sh` en vez de que cada stack cree la suya.
- **HTTPS como override, no como parte del archivo base**: mientras se
  prueba sin dominio real, `docker-compose.https.yml` no se usa y el
  archivo base queda simple y legible. Cuando haya dominio, se agrega con
  `-f` sin tocar el archivo base.
- **Volúmenes con bind mount (`./data/...`) en vez de volúmenes nombrados
  de Docker**: los datos de cada servicio quedan visibles como carpetas
  normales dentro del repo (ignoradas por git), lo que simplifica el script
  de backups del paso 7.

## Siguiente paso

[03 — Registrar Runner(s)](./03-gitlab-runner.md) *(pendiente)*
