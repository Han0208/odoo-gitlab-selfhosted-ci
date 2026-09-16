#!/usr/bin/env bash
# Crea la red Docker externa que comparten Traefik y los servicios que
# expone (GitLab y, más adelante, los ambientes Odoo). Se ejecuta una sola
# vez por servidor, antes de levantar cualquier stack.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${REPO_ROOT}/.env"

if [[ ! -f "${ENV_FILE}" ]]; then
    echo ".env no existe. Copia .env.example a .env primero." >&2
    exit 1
fi

set -a
source "${ENV_FILE}"
set +a

EDGE_NETWORK="${EDGE_NETWORK:-edge}"

if docker network inspect "${EDGE_NETWORK}" >/dev/null 2>&1; then
    echo "La red '${EDGE_NETWORK}' ya existe."
else
    docker network create "${EDGE_NETWORK}"
    echo "Red '${EDGE_NETWORK}' creada."
fi
