#!/bin/sh
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$PROJECT_DIR"

fail() {
    printf '\nError: %s\n' "$*" >&2
    exit 1
}

command -v docker >/dev/null 2>&1 || fail "Instalá Docker Desktop o Docker Engine con Compose."
docker compose version >/dev/null 2>&1 || fail "Falta Docker Compose v2 o superior."
docker info >/dev/null 2>&1 || fail "Iniciá Docker y ejecutá el script con sudo o como root si tu usuario no tiene acceso."

compose() {
    docker compose --env-file .dev/compose.env -f docker-compose.dev.yml "$@"
}

ACTION=${1:-start}
case "$ACTION" in
    start|stop|logs|status) ;;
    *) fail "Uso: sh dev.sh [start|stop|logs|status]" ;;
esac

if [ "$ACTION" != start ]; then
    [ -f .dev/compose.env ] || fail "Primero ejecutá sh dev.sh."
    case "$ACTION" in
        stop) compose down ;;
        logs) compose logs --tail=100 -f ;;
        status) compose ps ;;
    esac
    exit 0
fi

# Con sudo, los archivos generados pertenecen al usuario que lo invocó.
# Como root directamente, los contenedores y archivos usan UID/GID 0.
DEV_UID=$(id -u)
DEV_GID=$(id -g)
if [ "$DEV_UID" -eq 0 ] && [ -n "${SUDO_UID:-}" ] && [ -n "${SUDO_GID:-}" ]; then
    DEV_UID=$SUDO_UID
    DEV_GID=$SUDO_GID
fi
for identity in "$DEV_UID" "$DEV_GID"; do
    case "$identity" in
        ''|*[!0-9]*) fail "El UID y GID del usuario deben ser numéricos." ;;
    esac
done
export DEV_UID DEV_GID

[ -f sembrar/composer.lock ] && [ -f sembrar/package-lock.json ] \
    || fail "Cloná primero sembrar dentro de esta carpeta: git clone https://github.com/CostanzoPablo/sembrar.git"

mkdir -p .dev/mysql .dev/composer-cache .dev/npm-cache \
    sembrar/var sembrar/vendor sembrar/node_modules \
    sembrar/public/build sembrar/public/bundles sembrar/public/uploads

if [ ! -f .dev/compose.env ]; then
    (umask 077; printf 'DEV_UID=%s\nDEV_GID=%s\nDEV_PORT=%s\n' \
        "$DEV_UID" "$DEV_GID" "${DEV_PORT:-8002}" > .dev/compose.env)
fi

# Persistir la identidad para que stop/logs/status usen la misma configuración.
sed -e "s/^DEV_UID=.*/DEV_UID=$DEV_UID/" \
    -e "s/^DEV_GID=.*/DEV_GID=$DEV_GID/" .dev/compose.env > .dev/compose.env.tmp
mv .dev/compose.env.tmp .dev/compose.env
chmod 600 .dev/compose.env

# Nunca copiar .env.bck: contiene configuración ajena al entorno local.
if [ ! -f sembrar/.env ]; then
    (umask 077; printf 'APP_ENV=dev\nAPP_DEBUG=1\n' > sembrar/.env)
fi

on_error() {
    result=$?
    if [ "$result" -ne 0 ]; then
        printf '\nNo se pudo completar el inicio. Revisá la salida anterior.\n' >&2
        compose logs --tail=40 mysql php nginx >&2 || true
        printf '\nPodés volver a ejecutar sh dev.sh; los datos locales se conservan.\n' >&2
    fi
}
trap on_error EXIT

printf '\nPreparando PHP y MySQL...\n'
compose config --quiet
compose build php
compose up -d --wait --wait-timeout 180 mysql
compose stop nginx php node

if [ "$(id -u)" -eq 0 ]; then
    # No cambiar el dueño de MySQL, del código fuente ni del historial Git.
    chown "$DEV_UID:$DEV_GID" .dev .dev/compose.env sembrar/.env
    chown -R "$DEV_UID:$DEV_GID" .dev/composer-cache .dev/npm-cache \
        sembrar/var sembrar/vendor sembrar/node_modules \
        sembrar/public/build sembrar/public/bundles sembrar/public/uploads
fi

printf '\nInstalando dependencias PHP y preparando la base local...\n'
compose run --rm --no-deps php composer install --no-interaction --prefer-dist
compose run --rm --no-deps php composer check-platform-reqs
# Esquema actual para una base exclusivamente local; no importa el backup.
compose run --rm --no-deps php php bin/console doctrine:schema:update --force --no-interaction
compose run --rm --no-deps php php /opt/sembrar/init-dev.php
compose run --rm --no-deps php php bin/console assets:install public

printf '\nInstalando y compilando assets...\n'
compose run --rm --no-deps node npm ci --no-audit --no-fund
compose run --rm --no-deps node npm run dev

printf '\nIniciando la aplicación y el recompilador de assets...\n'
compose up -d --wait --wait-timeout 120
compose exec -T php php -r '
$context = stream_context_create(["http" => ["timeout" => 15]]);
$body = @file_get_contents("http://nginx/", false, $context);
if ($body === false) { fwrite(STDERR, "La aplicación no responde correctamente.\n"); exit(1); }
'
compose ps
DEV_EFFECTIVE_PORT=${DEV_PORT:-$(sed -n 's/^DEV_PORT=//p' .dev/compose.env)}
printf '\nProyecto listo: http://localhost:%s\n' "$DEV_EFFECTIVE_PORT"
printf 'Usuario local: %s\n' "${DEV_ADMIN_EMAIL:-admin@sembrar.local}"
printf 'Contraseña inicial: %s (si el usuario ya existía, conserva la anterior)\n' "${DEV_ADMIN_PASSWORD:-sembrar-dev}"
if [ "$(id -u)" -eq 0 ] && [ "$DEV_UID" -ne 0 ]; then
    printf 'Para detener: sudo sh dev.sh stop\n'
else
    printf 'Para detener: sh dev.sh stop\n'
fi
