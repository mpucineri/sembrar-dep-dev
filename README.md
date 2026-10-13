# Sembrar: entorno local de desarrollo

Necesitás Git y Docker Desktop iniciado (o Docker Engine con Compose v2.20+).
No necesitás instalar PHP, Composer, Node ni MySQL en tu computadora.
En Windows, usá WSL2 con integración de Docker habilitada.
En Linux, tu usuario debe poder ejecutar Docker sin sudo.

## Primer inicio

```sh
git clone https://github.com/mpucineri/sembrar-dep-dev.git
cd sembrar-dep-dev
git clone https://github.com/CostanzoPablo/sembrar.git
sh dev.sh
```

Abrí **http://localhost:8002** cuando el script diga “Proyecto listo”.
La primera ejecución necesita Internet y puede tardar varios minutos.

Usuario administrador local: `admin@sembrar.local`.
Contraseña inicial: `sembrar-dev`.
El usuario existente conserva su contraseña en los siguientes inicios.

El script construye PHP, espera a MySQL, instala dependencias desde los locks,
crea o sincroniza el esquema desde las entidades, crea el administrador,
compila assets y deja los contenedores ejecutándose en segundo plano.
La base empieza vacía; no se importa `backup/sembrar.sql`.
Usa `APP_ENV=dev` y desactiva el envío SMTP.
La cola propia de correos no se procesa: el emisor externo no está incluido.

## Uso diario

```sh
sh dev.sh         # Iniciar o actualizar dependencias, esquema y assets
sh dev.sh stop    # Detener, conservando los datos
sh dev.sh logs    # Ver logs; Ctrl+C termina la visualización
sh dev.sh status  # Ver el estado de los servicios
```

Editá el código dentro de `sembrar/`: PHP y Twig toman los cambios directamente.
JavaScript y CSS se recompilan automáticamente; recargá el navegador para verlos.
Después de actualizar repositorios o cambiar entidades/dependencias,
volvé a ejecutar `sh dev.sh`. La sincronización puede modificar tablas locales;
este flujo no sustituye las migraciones de producción.

## Archivos locales

```text
sembrar-dep-dev/
├── dev.sh
├── docker-compose.dev.yml
├── .dev/
│   ├── compose.env       # Puerto y usuario del host
│   ├── mysql/            # Datos persistentes de MySQL
│   ├── composer-cache/
│   └── npm-cache/
└── sembrar/
    ├── .env              # Creado si no existe
    ├── vendor/
    ├── node_modules/
    ├── var/              # Caché, sesiones y logs de Symfony
    └── public/           # build/, bundles/ y uploads/
```

Todo queda dentro de esta carpeta. No se usan volúmenes Docker externos.
Los datos y el repositorio anidado están excluidos del Git del deploy.
No borres `.dev/mysql/` si querés conservar la base local.

## Opciones y problemas frecuentes

Si el puerto está ocupado: `DEV_PORT=8003 sh dev.sh`.
Para hacerlo permanente, editá `DEV_PORT` en `.dev/compose.env`.
Para otro administrador, en el primer inicio:
`DEV_ADMIN_EMAIL=yo@example.test DEV_ADMIN_PASSWORD=mi-clave sh dev.sh`.
Si falla, revisá el error y `sh dev.sh logs`; corregilo y repetí `sh dev.sh`.
Si Docker no responde, iniciá Docker Desktop o el servicio Docker.
No ejecutes el script con sudo: las dependencias deben pertenecer a tu usuario.

Versiones: PHP 8.2.16, Composer 2.6.5, MySQL 8.0.36, Nginx 1.26.3,
Node 22.14.0. Symfony, Doctrine y Encore conservan las versiones de los locks.
Este script es exclusivamente para desarrollo local.
