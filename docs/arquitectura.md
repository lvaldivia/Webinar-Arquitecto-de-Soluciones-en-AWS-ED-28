# Decisiones de arquitectura

Este documento explica **por qué** la demo está construida así. Cada decisión está conectada con el concepto que enseña. Para el **cómo**, ver el código de Terraform en [`infra/`](../infra/) (cada archivo está comentado) o los pasos en la consola en [consola-aws.md](consola-aws.md).

## Punto de partida: una sola instancia

La versión "ingenua" de una app web es una única EC2 con todo adentro. Funciona hasta que:

- **la instancia o su AZ falla**: el sitio se cae (no hay alta disponibilidad);
- **llega más tráfico del que soporta**: el sitio se vuelve lento o se cae (no escala);
- **la IP de la instancia queda expuesta a internet**: toda la superficie de ataque apunta a ella.

Cada pieza de esta arquitectura resuelve uno de estos problemas.

```
Usuarios → CloudFront ─┬─ (default) → S3 privado (frontend estático, OAC)
                       └─ /api/*    → ALB → Auto Scaling Group (EC2 en 2 AZ) → contenedor de la API
```

---

## Multi-AZ: sobrevivir a la caída de un datacenter

**Decisión:** la VPC tiene 2 subredes en **2 zonas de disponibilidad distintas**. El ALB y el ASG usan ambas.

**Concepto:** una AZ es uno o varios datacenters con energía, red y refrigeración independientes. Si una falla, las demás de la región siguen funcionando. Distribuir las instancias en 2 AZ hace que la caída de una zona entera no tumbe el servicio.

**En la demo:** el panel A asigna un elemento por AZ (por ejemplo fuego para la `…a` y viento para la `…b`), así se ve que las respuestas vienen de ambas zonas.

## Application Load Balancer: un punto de entrada estable

**Decisión:** un ALB recibe todo el tráfico de la API y lo reparte entre las instancias registradas en un **target group**.

**Concepto:**

- Los clientes no conocen las instancias, solo el balanceador. Las instancias pueden aparecer y desaparecer (por escalado o por reemplazo) sin que nadie cambie una configuración.
- El ALB mismo es multi-AZ y lo administra AWS.

**En la demo:** el panel A muestra el contador por instancia: el reparto queda parejo.

## Health checks: detectar una instancia enferma

**Decisión:** el target group consulta `GET /health` cada 10 s. Con 2 fallos seguidos, el target pasa a `unhealthy`.

**Concepto:**

- El ALB **solo envía tráfico a targets sanos**. Si una instancia deja de responder, sale de la rotación sola.
- El health check debe ser **liviano y sin dependencias externas**. Si `/health` consultara la base de datos y esta tuviera un problema, el ALB marcaría **todas** las instancias como enfermas a la vez y el sitio se caería por completo, aunque las instancias estén bien. Por eso existen `/health` (superficial) y, en sistemas reales, checks más profundos aparte.

**En la demo:** al terminar una instancia aparecen algunas peticiones en rojo. Es el tiempo que el ALB tarda en confirmar la falla (intervalo × umbral). Después solo responde la instancia sana.

## Auto Scaling Group: recuperarse y escalar solo

**Decisión:** un ASG con **mínimo 2, deseado 2 y máximo 4** instancias, creadas desde un **launch template**.

**Concepto, dos funciones distintas:**

1. **Autorreparación:** el ASG mantiene siempre la capacidad deseada. Si una instancia muere, lanza otra.
2. **Escalado:** una política de **target tracking** mantiene la **CPU promedio cerca del 50 %**. Agrega instancias si sube y las quita si baja.

### El error típico: `health check type = EC2`

Por defecto, el ASG solo usa health checks de **EC2**, que revisan si la máquina virtual está viva. Si el **proceso de la aplicación** muere (el contenedor se cae, la app se cuelga):

| | ALB | ASG con check EC2 | ASG con check **ELB** |
|---|---|---|---|
| Ve el problema | ✅ target `unhealthy` | ❌ la VM sigue "running" | ✅ usa el resultado del ALB |
| Resultado | no le envía tráfico | **nunca la reemplaza** | la termina y lanza otra |

Con el check EC2, la capacidad baja de forma silenciosa. Por eso activamos **ELB health checks**.

### Grace period

Una instancia nueva necesita varios minutos para arrancar: instalar Docker, clonar y construir la imagen. Mientras tanto, `/health` falla. El **health check grace period** (300 s) evita que el ASG la mate antes de tiempo. Si es demasiado corto, el ASG entra en un **ciclo de reemplazos infinito**.

### ¿Por qué el escalado tarda minutos?

1. CloudWatch publica la métrica de CPU cada **1 minuto** (con monitoreo detallado) o cada **5 minutos** (básico).
2. La alarma de target tracking necesita **varios datos seguidos** por encima del objetivo, para no reaccionar a picos.
3. La instancia nueva debe arrancar, ejecutar el user data y pasar el health check.

El **scale-in** (quitar instancias) es más lento todavía, a propósito: quitar capacidad por error es peor que mantenerla un rato de más.

**En la demo:** el panel C (`POST /api/stress`) lleva la CPU de la instancia al 100 % con **un proceso por núcleo**. Se usan procesos y no hilos porque, por el GIL de Python, varios hilos no ocupan varios núcleos. Como el objetivo es la CPU **promedio**, hay que estresar todas las instancias: con 2 instancias, una al 100 % y otra al 0 % dan 50 %, que no supera el objetivo.

## Launch template, user data e inmutabilidad

**Decisión:** el launch template define todo lo necesario para crear una instancia idéntica: AMI, tipo, rol, security group, IMDS y **user data**. El user data clona este repo y ejecuta [`setup-instance.sh`](../scripts/setup-instance.sh).

**Concepto:**

- Las instancias son **ganado, no mascotas**: ninguna es especial y cualquiera se puede reemplazar. Nadie entra a configurarlas a mano.
- Para desplegar una versión nueva, lo ideal es un **Instance refresh**: el ASG reemplaza las instancias de a poco por otras nuevas que arrancan con el código actual. Actualizar "a mano" con `deploy-api.sh` funciona, pero cada instancia nueva que lance el ASG volvería a clonar el repo y las versiones podrían quedar mezcladas.
- En producción se suele ir un paso más allá: construir la imagen una vez, guardarla en **ECR** y que el user data solo la descargue. Así cada instancia arranca más rápido y corre exactamente el mismo artefacto.

## IMDSv2 y el hop limit

**Decisión:** el launch template exige **IMDSv2** (token obligatorio) con **hop limit = 2**.

**Concepto:**

- **IMDS** (`169.254.169.254`) le da a la instancia su propia metadata y credenciales temporales. IMDSv2 exige primero pedir un token con `PUT`, y eso bloquea ataques de tipo SSRF que solo pueden hacer `GET`.
- El **hop limit** es el TTL de la respuesta. Desde un contenedor hay un salto de red extra, así que con 1 la respuesta no llega. Con 2 sí.

**En la demo:** si el hop limit está mal, `/api/info` muestra `local-xxxx` en vez del `instance_id` real, y `deploy-api.sh` lo avisa.

## Security groups encadenados

**Decisión:**

| Security group | Acepta | Desde |
|---|---|---|
| ALB | HTTP 80 | prefix list `com.amazonaws.global.cloudfront.origin-facing` |
| Instancias | TCP 8080 | **el security group del ALB** |

**Concepto:**

- Referenciar un **security group como origen** (en vez de rangos de IP) significa "cualquier recurso que tenga ese SG". No importa cuántas instancias o IP tenga el ALB.
- La **prefix list administrada** de CloudFront impide saltarse CloudFront para atacar directo al ALB.
- **Limitación:** esa lista incluye las IP de **todas** las distribuciones de CloudFront, no solo la tuya. En producción se agrega un **header secreto** que CloudFront envía y el ALB valida en una regla del listener. O mejor, se usan **VPC origins** de CloudFront con un ALB interno.
- **No hay SSH:** el acceso a las instancias es con **Session Manager** (rol `AmazonSSMManagedInstanceCore`). Sin puerto 22, sin llaves y con auditoría.

## Subredes públicas vs. privadas

**Decisión (solo para la demo):** las instancias viven en **subredes públicas** con IPv4 pública.

**Lo recomendado en producción:**

```
Subredes públicas  → ALB, NAT Gateway
Subredes privadas  → instancias (sin IP pública; salen a internet por el NAT)
```

**Por qué no lo usamos:**

- El **NAT Gateway** se cobra por hora y por GB procesado, y para alta disponibilidad real se necesita **uno por AZ**. En una demo corta puede costar más que todo lo demás junto.
- La seguridad no depende de la subred sino del **security group**: aunque tengan IP pública, las instancias **solo aceptan tráfico del ALB**.

Las IPv4 públicas también tienen costo por hora, pero es mucho menor que el de un NAT Gateway.

## S3 privado + OAC: el frontend sin servidor

**Decisión:** el frontend (React compilado) se sube a un bucket con **Block Public Access** activado. CloudFront lo lee con **Origin Access Control (OAC)**.

**Concepto:**

- Los archivos estáticos no necesitan un servidor: S3 los guarda con alta durabilidad y sin administrar nada.
- **OAC** firma cada petición de CloudFront hacia S3. La política del bucket solo permite `s3:GetObject` al servicio CloudFront **y solo para tu distribución** (`AWS:SourceArn`). Nadie puede leer el bucket directo, ni siquiera conociendo la URL.
- Es mejor que el viejo "static website hosting" público: no hay bucket expuesto, se usa HTTPS de punta a punta en el lado del usuario, y es el mecanismo que AWS recomienda (el anterior, OAI, quedó como legado).

### Páginas de error para SPA

La app es una *single page application*. Con OAC, S3 responde **403** cuando un objeto no existe. Las respuestas personalizadas de CloudFront convierten 403/404 en `index.html` con código 200, y la app maneja la ruta.

## CloudFront: un solo dominio y caché en el edge

**Decisión:** una distribución con **dos orígenes** y **dos behaviors**:

| Behavior | Origen | Cache policy | Origin request policy |
|---|---|---|---|
| `*` (default) | S3 | **CachingOptimized** | (ninguna) |
| `/api/*` | ALB | **CachingDisabled** | **AllViewerExceptHostHeader** |

**Concepto:**

- **Mismo dominio, sin CORS:** el navegador carga la app y llama a la API en `dxxxx.cloudfront.net`. Para el navegador es el mismo origen. Por eso el frontend usa rutas relativas (`/api/info`) y no hay configuración de CORS.
- **Caché en el edge:** los estáticos se guardan en ubicaciones de CloudFront cercanas al usuario. El encabezado `X-Cache` lo muestra:
  - `Miss from cloudfront`: CloudFront tuvo que ir al origen.
  - `Hit from cloudfront`: lo sirvió desde su caché, sin tocar S3.
- **La API no se cachea:** cada respuesta depende de la instancia y del momento. `CachingDisabled` hace que todo `/api/*` vaya siempre al ALB.
- **`AllViewerExceptHostHeader`:** reenvía headers, cookies y query strings, pero no `Host`, para que el ALB reciba su propio nombre.
- **Invalidación:** al desplegar, `deploy-frontend.sh` invalida `/*` para que los edges descarten la versión anterior. Los JS/CSS llevan un hash en el nombre (Vite), así que cada build genera archivos nuevos. Lo único crítico es `index.html`, que además se sube con `Cache-Control: no-cache`.
- **HTTPS:** CloudFront da HTTPS con su certificado `*.cloudfront.net`. Entre CloudFront y el ALB usamos HTTP por simplicidad. En producción se usa un dominio propio con certificado de **ACM** y HTTPS también hacia el ALB.

**En la demo:** el panel D compara un estático (Miss → Hit) con la API (siempre Miss).

## Contenedores

**Decisión:** la API corre en Docker dentro de cada EC2. La imagen se basa en `python:3.12-slim`, corre con un **usuario no root**, escucha en el **puerto 8080** y tiene un `HEALTHCHECK`.

**Concepto:**

- El mismo artefacto corre igual en la laptop (`docker compose`) y en AWS.
- **No root + puerto > 1024:** si alguien compromete la app, no es root dentro del contenedor.
- `--restart always`: si el proceso muere, Docker lo levanta. Si la instancia se reinicia, también.
- En local, `docker compose up --scale api=3` y el nginx del frontend imitan al ALB, así que la demo del reparto también funciona sin AWS.

## Observabilidad

**Decisión:** la API escribe **logs JSON en stdout**, una línea por request, con `instance_id`, AZ, ruta, estado y duración. Los health checks del ALB van en nivel `DEBUG` para no llenar los logs.

**Concepto:** los logs estructurados se pueden consultar como datos. Si se instala el agente de CloudWatch (o se usa el driver `awslogs` de Docker), se pueden filtrar con **CloudWatch Logs Insights**, por ejemplo: "errores por instancia en los últimos 5 minutos".

---

## Qué cambiaría para producción

| Demo | Producción |
|---|---|
| Instancias en subredes públicas | Subredes privadas + NAT Gateway (uno por AZ) o VPC endpoints |
| User data clona y construye | Imagen construida en CI, guardada en ECR y versionada |
| HTTP entre CloudFront y ALB | Dominio propio, certificado ACM, HTTPS de punta a punta |
| Prefix list de CloudFront | + header secreto validado en el ALB, o VPC origins con ALB interno |
| Sin WAF | AWS WAF en CloudFront |
| Deploy manual con scripts | Pipeline CI/CD con su propio rol IAM |
| EC2 + Docker administrado por nosotros | Evaluar ECS/Fargate: mismo concepto, menos servidores que mantener |
| Logs en stdout del host | Agente de CloudWatch o driver `awslogs`, más alarmas |
| Estado de Terraform local | Backend remoto (S3) para trabajar en equipo, y despliegue desde CI/CD |
