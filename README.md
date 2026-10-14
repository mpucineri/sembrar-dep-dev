# Sembrar: entorno local de desarrollo

Necesitás Git y Docker Desktop iniciado (o Docker Engine con Compose v2.20+).
Configurá tu clave SSH en GitHub y verificá que tengas acceso a ambos repositorios.
No necesitás instalar PHP, Composer, Node ni MySQL en tu computadora.
En Windows, usá `dev-win.ps1` desde PowerShell con Docker Desktop configurado
para contenedores Linux y el motor WSL2.
En Linux podés ejecutar el script con sudo o directamente como root.

## Primer inicio

```sh
git clone git@github.com:mpucineri/sembrar-dep-dev.git
cd sembrar-dep-dev
git clone git@github.com:CostanzoPablo/sembrar.git
sudo sh dev.sh
```

Abrí **http://localhost:8002** cuando el script diga “Proyecto listo”.
La primera ejecución necesita Internet y puede tardar varios minutos.
Si ya sos root, usá `sh dev.sh`, sin sudo.
Con sudo, las dependencias, assets y archivos de Symfony pertenecen al usuario
que lo invocó; como root directamente, pertenecen a root.
MySQL conserva sus propios permisos. El script ajusta los permisos necesarios.

### Primer inicio en Windows

Desde Windows PowerShell 5.1 o PowerShell 7:

```powershell
git clone git@github.com:mpucineri/sembrar-dep-dev.git
cd sembrar-dep-dev
git clone git@github.com:CostanzoPablo/sembrar.git
powershell -NoProfile -ExecutionPolicy Bypass -File .\dev-win.ps1
```

El comando aplica la política de ejecución solamente a ese proceso.
El script usa los mismos servicios y datos locales que `dev.sh`. En Windows,
PHP y Node usan UID/GID 0 dentro de los contenedores, sin ejecutar `chown`
sobre los archivos del host.

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
sudo sh dev.sh         # Iniciar o actualizar dependencias, esquema y assets
sudo sh dev.sh stop    # Detener, conservando los datos
sudo sh dev.sh logs    # Ver logs; Ctrl+C termina la visualización
sudo sh dev.sh status  # Ver el estado de los servicios
```

En Windows (si tu política permite scripts, podés usar `.\dev-win.ps1`
directamente):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\dev-win.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\dev-win.ps1 stop
powershell -NoProfile -ExecutionPolicy Bypass -File .\dev-win.ps1 logs
powershell -NoProfile -ExecutionPolicy Bypass -File .\dev-win.ps1 status
```

Editá el código dentro de `sembrar/`: PHP y Twig toman los cambios directamente.
JavaScript y CSS se recompilan automáticamente; recargá el navegador para verlos.
Después de actualizar repositorios o cambiar entidades/dependencias,
volvé a ejecutar `sudo sh dev.sh` (o `sh dev.sh` como root).
La sincronización puede modificar tablas locales;
este flujo no sustituye las migraciones de producción.

## Archivos locales

```text
sembrar-dep-dev/
├── dev.sh
├── dev-win.ps1
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

Si el puerto está ocupado: `sudo DEV_PORT=8003 sh dev.sh`.
Para hacerlo permanente, editá `DEV_PORT` en `.dev/compose.env`.
Para otro administrador, en el primer inicio:
`sudo DEV_ADMIN_EMAIL=yo@example.test DEV_ADMIN_PASSWORD=mi-clave sh dev.sh`.
Como root, omití sudo en estos comandos.
En PowerShell, definí las opciones antes de ejecutar el script:

```powershell
$env:DEV_PORT = '8003'
$env:DEV_ADMIN_EMAIL = 'yo@example.test'
$env:DEV_ADMIN_PASSWORD = 'mi-clave'
powershell -NoProfile -ExecutionPolicy Bypass -File .\dev-win.ps1
```

Para guardar el puerto de forma permanente, editá `DEV_PORT` en `.dev/compose.env`.
Las variables `$env:` permanecen en la sesión de PowerShell hasta que las borres
o cierres la terminal. Las opciones del administrador aplican al crear el usuario.
Si falla, revisá el error y `sudo sh dev.sh logs`; corregilo y repetí el inicio.
Si Docker no responde, iniciá Docker Desktop o el servicio Docker.

Versiones: PHP 8.2.16, Composer 2.6.5, MySQL 8.0.36, Nginx 1.26.3,
Node 22.14.0. Symfony, Doctrine y Encore conservan las versiones de los locks.
Este script es exclusivamente para desarrollo local.
