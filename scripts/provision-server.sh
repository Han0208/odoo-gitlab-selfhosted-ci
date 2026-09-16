#!/usr/bin/env bash
# Provisiona un servidor Ubuntu 24.04 limpio para este proyecto:
# instala Docker Engine + Compose plugin y configura el firewall (ufw).
# Pensado para ejecutarse UNA VEZ, clonando este repo en el propio servidor.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${REPO_ROOT}/.env"

if [[ "${EUID}" -ne 0 ]]; then
    echo "Este script necesita privilegios de root. Ejecuta: sudo $0" >&2
    exit 1
fi

if [[ ! -f "${ENV_FILE}" ]]; then
    echo "No existe .env, creándolo a partir de .env.example..."
    cp "${REPO_ROOT}/.env.example" "${ENV_FILE}"
fi

set -a
source "${ENV_FILE}"
set +a

GITLAB_SSH_PORT="${GITLAB_SSH_PORT:-2222}"
DOCKER_VERSION="${DOCKER_VERSION:-28.5.2}"
TARGET_USER="${SUDO_USER:-$(logname)}"

echo "==> Instalando Docker Engine + Compose plugin (v${DOCKER_VERSION})"
apt-get update -y
apt-get install -y ca-certificates curl gnupg

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

UBUNTU_CODENAME="$(. /etc/os-release && echo "${VERSION_CODENAME}")"
cat > /etc/apt/sources.list.d/docker.list <<EOF
deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${UBUNTU_CODENAME} stable
EOF

apt-get update -y

# Se fija la versión exacta del paquete (no "la última") para evitar
# incompatibilidades como la de Docker 29, que subió la versión mínima de
# su API y rompió el auto-discovery de Traefik.
DOCKER_PKG_VERSION="$(apt-cache madison docker-ce | awk -v v="${DOCKER_VERSION}" '$3 ~ ("^5:" v "-") {print $3; exit}')"
if [[ -z "${DOCKER_PKG_VERSION}" ]]; then
    echo "No se encontró un paquete docker-ce para la versión ${DOCKER_VERSION}." >&2
    exit 1
fi

apt-get install -y --allow-downgrades \
    docker-ce="${DOCKER_PKG_VERSION}" \
    docker-ce-cli="${DOCKER_PKG_VERSION}" \
    containerd.io docker-buildx-plugin docker-compose-plugin

systemctl enable --now docker

# Sin esto, el usuario tendría que usar `sudo docker` para todo.
if ! id -nG "${TARGET_USER}" | grep -qw docker; then
    usermod -aG docker "${TARGET_USER}"
    echo "Usuario '${TARGET_USER}' agregado al grupo docker (cierra sesión y vuelve a entrar para que aplique)."
fi

echo "==> Configurando firewall (ufw)"
apt-get install -y ufw

ufw default deny incoming
ufw default allow outgoing
ufw allow OpenSSH
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow "${GITLAB_SSH_PORT}/tcp"
ufw --force enable

echo "==> Provisioning completado"
docker --version
docker compose version
ufw status verbose
