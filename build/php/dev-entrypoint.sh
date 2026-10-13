#!/bin/sh
set -eu

# Solo el entorno local permite workers root cuando el contenedor usa UID 0.
if [ "${1:-}" = php-fpm ] && [ "$(id -u)" -eq 0 ]; then
    set -- "$@" --allow-to-run-as-root
fi

exec docker-php-entrypoint "$@"
