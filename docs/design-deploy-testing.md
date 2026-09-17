# Diseño: deploy-testing sin Dockerfile ni scripts por proyecto

> 📝 **Estado: diseño propuesto, aún no implementado.** Este documento no es
> una guía paso a paso verificada como `01-` o `02-` — es la arquitectura
> acordada para los pasos 3-6 del roadmap (Runner, imagen base de Odoo,
> pipeline, deploy dinámico por rama), escrita antes de construirlos para no
> perder las decisiones. Cuando se implemente y se verifique en el servidor
> de pruebas, esto se convierte en la guía numerada correspondiente.

## El problema que resuelve

Hoy, en muchos setups de infraestructura Odoo self-hosted, levantar CI/CD
para un proyecto nuevo implica copiar un Dockerfile al repo del proyecto y
registrar/configurar un Runner específico. Un repo que debería contener
*solo módulos* termina cargando infraestructura — y crear un proyecto nuevo
significa repetir ese trabajo cada vez.

**Objetivo de este diseño:** que un repo de proyecto contenga *únicamente*
sus módulos de Odoo (y opcionalmente un `requirements.txt` si necesita
dependencias de Python extra). Nada de Dockerfile, nada de scripts de CI,
nada de configuración de Runner por proyecto. Toda esa infraestructura vive
una sola vez, centralizada, en este repo (`odoo-gitlab-selfhosted-ci`).

## Lo que ve alguien usando un proyecto

1. Crea un repo en el GitLab self-hosted con sus módulos Odoo (uno o
   varios, directo en la raíz del repo — cada carpeta con un
   `__manifest__.py` es un addon).
2. Si necesita dependencias de Python fuera de las que ya trae Odoo, agrega
   un `requirements.txt`.
3. Configura dos variables CI/CD del proyecto (Settings → CI/CD →
   Variables, vía UI de GitLab, sin tocar archivos): `ODOO_VERSION` (ej.
   `19`) y `ODOO_EDITION` (`community` o `enterprise`).
4. Push a una rama → a los pocos minutos tiene un Odoo levantado en
   `https://<rama>.<proyecto>.<ip>.nip.io` con sus módulos listos para
   instalar. Nada más que hacer.

## Arquitectura en dos niveles

### Nivel 1 — imágenes base (se construyen una sola vez, en este repo)

Una matriz finita de imágenes `odoo-ci:<version>-<edition>` (ej.
`odoo-ci:19-community`, `odoo-ci:18-enterprise`) se construye en el pipeline
*de este repo* (no en el de cada proyecto) y se publica al Container
Registry del propio GitLab self-hosted. Contienen Odoo + sus dependencias
de sistema, y si son `enterprise`, el código de Odoo Enterprise ya clonado
adentro.

**Por qué:** el build de Odoo (apt, dependencias del sistema, y para
enterprise el clone del repo privado) es lo mismo para todos los proyectos
que comparten versión+edición — no tiene sentido repetirlo por proyecto.
Solo se reconstruye cuando sale una versión nueva de Odoo o hay que aplicar
un parche de seguridad, no en cada push de cada proyecto.

### Nivel 2 — ambiente por proyecto (sin build, solo `docker compose up`)

El pipeline de deploy-testing (compartido, ver más abajo) no hace
`docker build`. Solo:

- Usa como base la imagen `odoo-ci:${ODOO_VERSION}-${ODOO_EDITION}` del
  Nivel 1.
- Monta el checkout del repo del proyecto como volumen de addons
  (`--addons-path` extra apuntando a la raíz del repo clonado).
- Si existe `requirements.txt` en el repo del proyecto, corre
  `pip install -r requirements.txt` como paso previo a levantar Odoo.
- Levanta `docker compose up` (Odoo + Postgres) con labels de Traefik para
  el subdominio `<rama>.<proyecto>.<ip>.nip.io`.

**Por qué:** esto es literalmente la respuesta a "¿se puede automatizar
Docker sin tener un Dockerfile por proyecto?" — sí, usando una imagen ya
armada y montando el código como volumen en vez de "hornearlo" (`COPY`) en
una imagen nueva cada vez. Es más rápido (no hay build) y el repo del
proyecto no necesita saber nada de Docker.

## Enterprise vs Community

El código de Odoo Enterprise es privado (repo de GitHub, requiere
suscripción). La credencial de acceso a ese repo se configura **una sola
vez, en este repo** (el que construye las imágenes base), no por proyecto
cliente — un proyecto que declara `ODOO_EDITION=enterprise` simplemente
consume la imagen `odoo-ci:<version>-enterprise` ya armada; nunca necesita
ni ve esa credencial.

**Por qué:** evita que cada proyecto tenga que gestionar su propia
credencial de acceso a un repo privado de terceros — un único punto de
gestión, más simple y más seguro (menos lugares donde esa credencial pueda
filtrarse).

## Pipeline compartido, no uno por proyecto

En vez de que cada repo cliente tenga su propio `.gitlab-ci.yml`, usar el
campo "CI/CD configuration file" de GitLab (Settings → CI/CD → General
pipelines), que permite apuntar a un archivo de pipeline **en otro
proyecto** con la sintaxis `ruta/al/archivo.yml@grupo/proyecto`. Así el
repo cliente puede no tener ningún archivo de CI propio.

⚠️ *A confirmar durante la implementación:* verificar que esta opción esté
disponible en la versión de GitLab CE que se use (no es exclusiva de
Enterprise Edition en las versiones recientes, pero hay que probarlo en el
servidor real antes de darlo por sentado). Si por algún motivo no
funcionara como se espera, el fallback es un `.gitlab-ci.yml` de una sola
línea en cada proyecto:

```yaml
include:
  - project: 'infra/odoo-gitlab-selfhosted-ci'
    file: 'templates/gitlab-ci/odoo-deploy-testing.yml'
```

Sigue siendo "sin scripts propios" — es una sola línea que nunca cambia
entre proyectos, sin lógica de CI que mantener por proyecto.

## Convención de addons-path

**No alcanza con escanear solo la raíz del repo.** Un módulo puede estar
anidado varios niveles abajo — típicamente dentro de un submodule que a su
vez agrupa varios addons en subcarpetas (ej. `terceros/oca-hr/hr_extra/`),
o en carpetas intermedias de organización. El `--addons-path` de Odoo solo
mira un nivel de profundidad por cada ruta que se le pase (no recorre
subcarpetas recursivamente por su cuenta), así que si solo se le pasa la
raíz del repo, cualquier módulo a 2+ niveles de profundidad queda **sin
instalar, sin ningún error visible** — el peor tipo de falla.

Por eso el paso de armado del ambiente debe incluir un script propio
(corrido antes de levantar Odoo) que:

1. Recorre **todo** el árbol del repo del proyecto de forma recursiva
   (incluyendo dentro de submodules ya clonados), buscando cualquier
   carpeta que contenga un `__manifest__.py`, sin importar la profundidad.
2. Por cada carpeta de módulo encontrada, toma su carpeta **padre**
   (porque eso es lo que Odoo espera en cada entrada de `--addons-path`:
   un directorio cuyos hijos directos son addons).
3. Arma el `--addons-path` final como la lista de esos directorios padre,
   deduplicados (varios módulos que comparten padre solo aportan una
   entrada).
4. Excluye del recorrido `.git` (y otros directorios de control de
   versiones) por rendimiento — no porque puedan tener manifests válidos,
   sino porque nunca los tienen y recorrerlos es tiempo perdido.

**Por qué:** montar solo la raíz del repo como addons-path es la trampa
fácil que parece funcionar en la demo (donde los módulos están todos al
mismo nivel) y falla en silencio en el caso real, con submodules anidados
a distinta profundidad — que es exactamente el escenario que este diseño
tiene que soportar.

## Base de datos: Postgres compartido, no uno por instancia

Un único contenedor Postgres compartido por **todos** los ambientes de
testing (de todos los proyectos y ramas), no un Postgres por instancia
Odoo. Cada ambiente crea su propia base de datos y su propio rol dentro de
ese servidor compartido.

**Por qué:** cada contenedor Postgres reserva memoria y procesos de fondo
propios (WAL writer, autovacuum, stats collector, checkpointer) aunque esté
vacío — con decenas de ambientes de testing livianos y de uso puntual (1-2
personas por rama, no tráfico real), levantar un Postgres completo por cada
uno es desperdiciar recursos que el servidor no tiene de sobra. Postgres
soporta cientos de bases de datos inactivas sin costo relevante; el límite
real no es "cuántas bases" sino conexiones activas concurrentes
(`max_connections`, default 100) — hay que subirlo (ej. a 300) y, si en la
práctica se queda corto, agregar un `pgbouncer` delante como pooler en vez
de seguir subiendo el límite.

Trade-off aceptado explícitamente: si el Postgres compartido se cae, caen
todos los ambientes de testing a la vez, de todos los proyectos. Para datos
de prueba efímeros es un riesgo aceptable — no es la fuente de verdad de
nada.

**Aislamiento entre proyectos:** cada ambiente crea su propio rol Postgres
con permisos limitados solo a su propia base (`GRANT ALL ON DATABASE x TO
rol_x`, nada más) — nunca un superusuario compartido entre instancias. Así
una instancia de un proyecto no puede ni ver la existencia de la base de
otro.

### Convención de nombres (servicio Docker = base de datos = rol)

El nombre debe ser el mismo, determinístico, y sobrevivir a redeploys de la
misma rama (para que reusar el ambiente reutilice también su base de datos,
en vez de perder los datos de prueba en cada push).

1. **Incluye el proyecto, no solo la rama.** Con ~10 proyectos compartiendo
   el mismo servidor, dos proyectos distintos pueden tener una rama con el
   mismo nombre. Base: `<proyecto>_<rama>`.
2. **Los nombres de rama son input no confiable.** Git permite casi
   cualquier caracter en un nombre de rama (mayúsculas, `/`, unicode, muy
   largo) y cualquiera con acceso de push puede elegirlo — nunca hay que
   interpolar ese string directo en un `CREATE DATABASE` (riesgo de
   inyección SQL) ni asumir que es válido como nombre de servicio Docker o
   subdominio DNS sin sanitizar.
3. **Sanitización determinística:** minúsculas, todo lo que no sea
   `[a-z0-9_]` se reemplaza por `_`, y se agrega un sufijo hash corto y
   determinístico (ej. 8 caracteres de un sha1 de `proyecto/rama`) — mismo
   input siempre produce el mismo nombre, y el hash elimina el riesgo de
   colisión entre dos ramas que sanitizadas (o truncadas al límite de 63
   bytes de Postgres) queden parecidas.
4. Ese slug (`<proyecto>_<rama-sanitizada>_<hash8>`) se usa tal cual para
   el servicio Docker, la base de datos y el rol Postgres. Para el
   subdominio DNS (que prefiere guiones, no `_`) se deriva del mismo slug
   reemplazando `_` por `-` — mismo origen, adaptado al charset de cada
   sistema en vez de un string crudo reusado a ciegas en los tres lugares.
5. **Creación idempotente.** El script de provisioning de base de datos
   chequea si la base ya existe antes de crearla (Postgres no tiene
   `CREATE DATABASE IF NOT EXISTS` nativo) — un redeploy de la misma rama
   reutiliza la base existente, no la recrea. Solo se borra (`DROP
   DATABASE`, tras terminar conexiones activas con
   `pg_terminate_backend`) en el cleanup real al cerrar la rama/MR.

## Filestore: mismo tratamiento que la base de datos

Postgres guarda las filas, pero los adjuntos/documentos de Odoo viven en
disco (`filestore`), fuera de la base. Si la base se reutiliza entre
redeploys (ver convención de nombres arriba) pero el contenedor se recrea
desde cero cada vez sin persistir el filestore, quedan registros en la
base que apuntan a archivos que ya no existen — adjuntos e imágenes rotas,
en silencio.

**Solución:** un volumen persistente (bind mount) con el mismo nombre
determinístico que la base (`<proyecto>_<rama-sanitizada>_<hash8>`), que
sobrevive redeploys de la misma rama y se borra junto con la base en el
cleanup real.

## Datos de prueba: clonar desde una base plantilla

Un ambiente recién creado, vacío y sin datos demo, sirve poco para QA
funcional real. En vez de correr la instalación demo de Odoo desde cero en
cada ambiente nuevo (lento), aprovechar que Postgres permite clonar una
base completa como plantilla: `CREATE DATABASE nueva TEMPLATE
plantilla_con_demo`.

Se mantiene una base "plantilla" (una por versión/edición de Odoo,
similar a la matriz de imágenes base) precargada con datos demo o un dump
anonimizado, actualizada periódicamente. Cada ambiente nuevo se crea
clonándola — segundos en vez de minutos, y con datos realistas desde el
primer arranque.

## Instalación/actualización automática de módulos

El pipeline debe correr, al levantar el ambiente, `-i` sobre los módulos
nuevos (detectados por primera vez) y `-u` sobre los que ya existían en un
redeploy — usando la misma lista de módulos que encontró el script
recursivo de addons-path. Sin este paso, alguien tendría que entrar
manualmente a Apps a instalar cada módulo, lo que rompe el objetivo
original ("push → módulo listo para instalar sin hacer nada más").

## Cleanup: usar Environments nativo de GitLab, no un script custom

En vez de un cron/script propio para destruir ambientes, usar el feature
de **Environments** de GitLab CI:

- `on_stop`: un job que GitLab dispara automáticamente cuando se borra la
  rama o se cierra/mergea el MR — ahí van el `docker compose down`, el
  `DROP DATABASE` (con `pg_terminate_backend` previo) y el borrado del
  volumen de filestore.
- `auto_stop_in`: TTL automático (ej. `1 week`) para ambientes que quedan
  abandonados sin que nadie cierre la rama — red de seguridad además del
  `on_stop`.

**Por qué:** es soporte nativo de GitLab pensado exactamente para esto
("Review Apps"), en vez de reinventar la lógica de limpieza a mano.

## Exposición de los ambientes de testing (decisión diferida, no definitiva)

Los subdominios `nip.io` resuelven públicamente a la IP real del servidor
— si ese servidor tuviera IP pública, cualquiera que conozca o adivine la
URL de una rama entraría sin login a un Odoo con datos de prueba/demo.

**Decisión actual (2026-09-17):** por ahora no se agrega autenticación
extra (sin BasicAuth de Traefik), porque el servidor de pruebas es de red
privada y no hay forma de probar el caso de red pública todavía. **Esto no
es una decisión final** — cuando el servidor real quede expuesto
públicamente, hay que resolver esto (BasicAuth de Traefik por delante de
los subdominios de testing es la opción más simple) antes de abrir el
servidor a internet.

## Relación con el roadmap

Esto cubre, en orden:

- **Paso 3 (Runner):** el/los Runner(s) de este repo ejecutan tanto el
  build de las imágenes base (Nivel 1) como los pipelines de
  deploy-testing de cada proyecto cliente (Nivel 2).
- **Paso 4 (imagen base de Odoo):** la matriz `odoo-ci:<version>-<edition>`
  descrita arriba, construida y versionada en este repo.
- **Paso 5 (pipeline build+test) y paso 6 (deploy dinámico por rama):** el
  `templates/gitlab-ci/odoo-deploy-testing.yml` compartido descrito arriba.

## Riesgos / cosas a validar al implementar

- Confirmar el soporte real de "CI/CD configuration file externo" en la
  versión de GitLab CE instalada.
- Definir política de recursos: cuántos ambientes de testing simultáneos
  soporta el servidor antes de necesitar límites o colas (ver también
  sección de Postgres compartido — el límite probablemente lo marque la
  RAM que consume cada instancia Odoo, no la base de datos).
- Decidir cómo se actualiza/refresca periódicamente la base plantilla con
  datos demo (manual vs automatizado) y si hace falta anonimizar datos
  reales si en algún momento se usa un dump real en vez de demo data de
  Odoo.
- Revisar exposición pública de los ambientes de testing (BasicAuth de
  Traefik) el día que el servidor real quede accesible desde internet —
  ver sección dedicada arriba.
