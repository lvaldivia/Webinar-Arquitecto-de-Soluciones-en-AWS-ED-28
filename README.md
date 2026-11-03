# Grimorios en la Nube

### Arquitectura web escalable y de alta disponibilidad en AWS

Demo educativa para pasar de **una sola instancia** a una arquitectura que **escala sola** y **sobrevive a la caída de un servidor o de una zona de disponibilidad**. Incluye una interfaz interactiva con temática de grimorios y magia elemental: en ella cada panel enseña un concepto y deja verlo en vivo.

| Concepto | Qué se ve en la demo |
|---|---|
| **Application Load Balancer** | Las respuestas se reparten entre instancias de 2 AZ |
| **Health checks** | Una instancia cae, el ALB deja de enviarle tráfico |
| **Auto Scaling Group** | Reemplaza la instancia caída y agrega instancias cuando sube la CPU |
| **S3 privado + OAC** | El frontend vive en un bucket que nadie puede leer directo |
| **CloudFront** | Un solo dominio para frontend y API, y caché en el edge (`Miss` → `Hit`) |

---

## Arquitectura

```mermaid
flowchart LR
    U["👤 Usuarios"] --> CF["CloudFront"]
    CF -- "default (*)" --> S3[("S3 privado<br/>frontend estático")]
    CF -- "/api/*" --> ALB["Application<br/>Load Balancer"]

    subgraph VPC["VPC"]
        ALB
        subgraph AZA["Zona A"]
            EC2A["EC2<br/>contenedor API :8080"]
        end
        subgraph AZB["Zona B"]
            EC2B["EC2<br/>contenedor API :8080"]
        end
        ASG{{"Auto Scaling Group<br/>min 2 · max 4 · CPU 50 %"}}
    end

    ALB --> EC2A
    ALB --> EC2B
    ASG -. "lanza / reemplaza" .-> EC2A
    ASG -. "lanza / reemplaza" .-> EC2B
    S3 -. "solo vía OAC" .- CF
```

- El navegador **solo habla con CloudFront**. Todas las llamadas a la API usan rutas relativas (`/api/...`), y como todo sale del mismo dominio **no hace falta CORS**.
- El **ALB solo acepta tráfico de CloudFront** (managed prefix list), y las **instancias solo aceptan tráfico del ALB** (security group).
- Cada EC2 clona este repo al arrancar (user data), construye la imagen de la API y la corre en Docker.

Las razones detrás de cada decisión están en [docs/arquitectura.md](docs/arquitectura.md).

---

## Contenido del repo

```
├── backend/           API en Python + FastAPI (Dockerfile, tests)
├── frontend/          React + Vite + TypeScript (Dockerfile con nginx para local)
├── infra/             Terraform: toda la infraestructura de AWS
├── scripts/
│   ├── infra-up.sh          despliega todo (Terraform + frontend) con un comando
│   ├── infra-destroy.sh     borra todo (pide confirmación)
│   ├── user-data.sh         se pega en el launch template (despliegue por consola)
│   ├── setup-instance.sh    prepara la EC2 (Docker, git) y levanta la API
│   ├── deploy-api.sh        build + reinicio del contenedor de la API
│   ├── deploy-frontend.sh   build del frontend + subida a S3 + invalidación
│   ├── demo-check.sh        comprueba reparto y caché desde la terminal
│   └── tf-outputs.sh        funciones para leer los outputs de Terraform
├── docs/
│   ├── arquitectura.md      decisiones de diseño y conceptos
│   └── consola-aws.md       guía paso a paso para crear todo en la consola
├── docker-compose.yml       entorno local
└── .env.example             variables de configuración
```

### API

| Método | Ruta | Descripción |
|---|---|---|
| `GET` | `/health` | Health check del ALB. Liviano: `{"status":"ok"}`, sin dependencias |
| `GET` | `/api/health` | Igual, pero accesible por CloudFront |
| `GET` | `/api/info` | `instance_id`, `availability_zone`, `region`, `hostname`, `version`, `timestamp` |
| `POST` | `/api/spell` | Hechizo aleatorio (nombre, elemento, poder 1-100) y quién lo lanzó |
| `POST` | `/api/stress` | Body `{"seconds": 60}`. Sube la CPU en segundo plano (máx. 300 s). `202` aceptado / `409` ya hay uno activo |
| `GET` | `/api/grimoires` | Lista estática de grimorios de ejemplo |

La metadata de la instancia se lee con **IMDSv2**. Si IMDS no responde en 1 s (en local), se usan valores simulados (`local-xxxx`, `local-az`).

### Variables de entorno

| Variable | Por defecto | Uso |
|---|---|---|
| `APP_VERSION` | `1.0.0` (en EC2: el commit) | Versión que muestra `/api/info` |
| `STRESS_MAX_SECONDS` | `300` | Tope de `/api/stress` |
| `LOG_LEVEL` | `INFO` | `DEBUG` también registra los health checks |

Para cambiarlas, copia `.env.example` como `.env`. Docker Compose y `deploy-api.sh` lo leen. El `.env` está en `.gitignore`.

---

## Requisitos

| Herramienta | Para qué |
|---|---|
| [Docker](https://docs.docker.com/get-docker/) con Compose v2 | Entorno local y build de imágenes |
| [Node.js](https://nodejs.org/) ≥ 22 (recomendado el LTS) | Desarrollar o compilar el frontend (opcional: los scripts pueden compilar dentro de Docker) |
| [Python](https://www.python.org/) ≥ 3.12 | Correr los tests del backend sin Docker |
| [AWS CLI v2](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) | Credenciales, subir el frontend a S3 e invalidar CloudFront |
| [Terraform](https://developer.hashicorp.com/terraform/install) ≥ 1.10 | Crear y destruir la infraestructura de AWS |
| Git y una terminal bash | En Windows: Git Bash o WSL |

---

## Desarrollo local

### 1. Todo con Docker Compose

```bash
docker compose up --build
```

Abre **http://localhost:8080**. El nginx del frontend hace de "CloudFront": sirve los estáticos y reenvía `/api/*` a la API.

Para ver el reparto de carga como en AWS, levanta **3 réplicas** de la API:

```bash
docker compose up --build --scale api=3
```

En el panel A verás 3 `instance_id` distintos (`local-xxxx`). En local todas las réplicas comparten la AZ `local-az`, así que el color se asigna por instancia. También puedes comprobarlo desde la terminal:

```bash
bash scripts/demo-check.sh http://localhost:8080
```

Prueba a detener una réplica con `docker stop grimorios-api-2`: el tráfico sigue llegando a las demás.

### 2. Tests del backend

```bash
cd backend
python -m venv .venv
source .venv/bin/activate        # Windows (PowerShell): .venv\Scripts\Activate.ps1
pip install -r requirements-dev.txt
pytest
```

Los tests simulan IMDS y no lanzan procesos de estrés reales.

### 3. Frontend con recarga en caliente (opcional)

Con el stack de compose (o la API) corriendo en el puerto 8080:

```bash
cd frontend
npm ci
npm run dev        # http://localhost:5173, reenvía /api a localhost:8080
```

---

## Despliegue en AWS

> ⚠️ **Esto genera costos** desde el primer minuto (ALB, IPv4 públicas e instancias). Antes de empezar lee [Costos y limpieza](#costos-y-limpieza) y crea una alerta en AWS Budgets.

Hay dos caminos para crear la misma arquitectura:

- **Opción A, Terraform (recomendada):** un comando crea todo y otro lo borra todo. Ideal para ensayar o para tener la demo lista antes de una clase.
- **Opción B, consola:** se crea a mano, paso a paso, para entender cada pieza.

En ambos casos, primero:

### Paso 0: Sube tu copia del repo a GitHub

Las instancias clonan el repo al arrancar, así que **debe ser público** (o tienes que adaptar el user data).

### Opción A: Terraform

```bash
# 1. Configura tus valores (repo y perfil de AWS CLI)
cp infra/terraform.tfvars.example infra/terraform.tfvars
#    edita repo_url y aws_profile

# 2. Despliega todo: infraestructura + frontend, y espera a que las instancias estén sanas
bash scripts/infra-up.sh
```

`infra-up.sh` hace `terraform init` y `terraform apply` (te pide confirmar). Después compila y sube el frontend, y espera a que haya 2 instancias `healthy`. Al final imprime la URL de CloudFront. Tarda de **10 a 15 minutos**: CloudFront es lo más lento.

El código de [`infra/`](infra/) replica uno a uno los pasos de la guía de consola, con comentarios que explican cada decisión. Los archivos clave para mostrar en clase son `compute.tf` (launch template, ASG y health check ELB) y `cloudfront.tf`.

| Archivo | Qué crea |
|---|---|
| `network.tf` | VPC, 2 subredes públicas en 2 AZ (y la versión privada con NAT, comentada) |
| `security_groups.tf` | ALB ← prefix list de CloudFront; instancias ← ALB:8080 |
| `iam.tf` | Rol de las instancias con SSM (sin SSH) |
| `compute.tf` | Launch template (AL2023, IMDSv2 hop 2), ASG 2/2/4 con health check ELB y target tracking CPU 50 % |
| `alb.tf` | ALB, target group (`/health`) y listener |
| `frontend.tf` | Bucket privado, OAC y política del bucket |
| `cloudfront.tf` | Distribución con 2 orígenes, `/api/*` sin caché y errores de SPA |
| `outputs.tf` | URL, bucket, distribución, ALB y ASG (los usan los scripts) |

Con la infraestructura de Terraform, los scripts leen los outputs solos y no hace falta pasarles argumentos:

```bash
bash scripts/demo-check.sh       # comprueba reparto y caché
bash scripts/deploy-frontend.sh  # vuelve a publicar el frontend
bash scripts/infra-destroy.sh    # BORRA TODO (pide escribir "destruir")
```

> 🔒 `infra/terraform.tfvars` y `terraform.tfstate` están en `.gitignore`: el estado contiene IDs de tu cuenta y **nunca** debe subirse a un repo público. El estado es local (en `infra/`), así que destruye la infraestructura desde la misma máquina en la que la creaste.

### Opción B: Consola

La guía detallada está en **[docs/consola-aws.md](docs/consola-aws.md)**. Antes de empezar, en `scripts/user-data.sh` cambia `REPO_URL` por la URL de tu repo. El orden es importante:

#### Paso 1: Infraestructura y API

Sigue [docs/consola-aws.md](docs/consola-aws.md), pasos 1 a 7:

1. VPC con 2 subredes públicas en 2 AZ
2. Security groups (ALB ← CloudFront, EC2 ← ALB)
3. Rol IAM de la instancia (SSM, sin SSH)
4. Launch template (Amazon Linux 2023, IMDSv2 con hop limit 2 y el user data)
5. Target group (HTTP 8080, health check `/health`)
6. Application Load Balancer
7. Auto Scaling Group (2/2/4, health check **ELB**, target tracking CPU 50 %)

Al crear el ASG, cada instancia ejecuta el user data: instala Docker, clona el repo y levanta la API. **Tarda unos 3 a 5 minutos** hasta que los targets aparecen `healthy` en el target group.

#### Paso 2: Frontend (S3 + CloudFront)

Sigue los pasos 8 y 9 de la guía: crea el bucket privado y la distribución de CloudFront (con OAC y el behavior `/api/*` → ALB). Después sube el frontend:

```bash
bash scripts/deploy-frontend.sh <nombre-del-bucket> <id-de-la-distribucion>
```

El script compila el frontend (con Node, o con Docker si no hay Node), hace `aws s3 sync --delete` e invalida la caché de CloudFront.

> ⏳ **CloudFront tarda varios minutos en desplegarse** la primera vez (estado *Deploying*). Hasta que no figure la fecha en *Last modified*, la URL puede devolver errores o contenido viejo.

#### Paso 3: Comprobar

```bash
bash scripts/demo-check.sh https://dxxxxxxxxxxxxx.cloudfront.net
```

Deberías ver respuestas de **dos instancias en dos AZ distintas** y el estático pasando de `Miss` a `Hit`.

### Actualizar la API

- **Forma recomendada:** en EC2 → Auto Scaling Groups → tu ASG → *Instance refresh* → *Start* (o con la CLI: `aws autoscaling start-instance-refresh --auto-scaling-group-name grimorios-asg`). El ASG reemplaza las instancias de a poco, sin cortar el servicio. Cada instancia nueva clona el código más reciente, y `/api/info` muestra el commit en `version`.
- **Forma manual** (para entender el contraste): conéctate con *Session Manager* a cada instancia y ejecuta `sudo bash /opt/grimorios/scripts/deploy-api.sh`.

---

## Guion de la demo

Abre la URL de CloudFront en el proyector y, al lado, la consola de AWS.

### Acto 1: Reparto de tráfico (panel A)

- **Qué hacer:** deja correr el panel "¿Qué grimorio respondió?" (consulta `/api/info` cada 2 s).
- **Qué observar:**
  - Los hechizos alternan entre dos elementos: por ejemplo **fuego** para la AZ `…a` y **viento** para la `…b`.
  - Los contadores por instancia y por AZ quedan parejos.
- **Mensaje:** el ALB reparte las peticiones entre instancias sanas de distintas zonas. Si se cae una zona entera, la otra sigue atendiendo.

### Acto 2: Una instancia cae (paneles A y consola)

- **Qué hacer:** en EC2 → Instances, **termina** una de las instancias.
- **Qué observar:**
  1. Puede aparecer alguna petición **en rojo** (502) en el registro de hechizos mientras el ALB detecta la caída.
  2. En el **target group → Targets**, la instancia pasa a `draining` o `unhealthy`, y todo el tráfico va a la instancia que queda.
  3. En el **ASG → Activity**, el ASG detecta que tiene 1 instancia de 2 y **lanza un reemplazo**. A los pocos minutos aparece un `instance_id` nuevo en el panel A.
- **Mensaje:** alta disponibilidad no significa "nunca falla", sino "se recupera sola". Comenta el error típico: si el ASG usa health checks de tipo **EC2** en vez de **ELB**, no reemplaza una instancia cuya *aplicación* murió pero cuya máquina sigue encendida.

### Acto 3: Modo estrés, el ASG escala (panel C)

- **Qué hacer:** con 180 a 300 s, presiona **"Desatar estrés"** varias veces, hasta que **todas** las instancias respondan "ya está estresada".
- **Qué observar:**
  - En **CloudWatch** (o en la pestaña *Monitoring* del ASG), la CPU promedio supera el 50 %.
  - En unos **5 a 10 minutos**, el **ASG → Activity** muestra "Launching a new EC2 instance" y aparece una tercera instancia en el panel A.
- **Mensaje:** target tracking ajusta la capacidad para mantener la métrica cerca del objetivo. El escalado **no es instantáneo**: hay métricas cada minuto, alarmas con varios datos y el arranque de la instancia. Al terminar, el *scale-in* tarda más, porque es conservador a propósito.

### Acto 4: El caché de CloudFront (panel D)

- **Qué hacer:** presiona **"Mirar estático"** dos veces y luego **"Mirar /api"**.
- **Qué observar:**
  - El estático pasa de `Miss from cloudfront` a `Hit from cloudfront`, y aparece el encabezado `Age`.
  - La API siempre dice `Miss`, porque `/api/*` tiene el caché deshabilitado.
  - Si ejecutas `deploy-frontend.sh` (que invalida), el estático vuelve a `Miss`.
- **Mensaje:** el contenido estático se sirve desde el edge más cercano, sin tocar S3. Es más rápido para el usuario y le quita carga al origen. Lo dinámico pasa siempre al backend.

---

## Costos y limpieza

**Esta demo no es gratis.** Algunos recursos **se cobran por hora aunque no reciban tráfico**:

- **Application Load Balancer:** se cobra cada hora que exista, más su consumo (LCU).
- **Direcciones IPv4 públicas:** AWS cobra por cada IPv4 pública asignada, y cada instancia tiene una.
- **Instancias EC2:** mínimo 2 corriendo todo el tiempo (hasta 4 si escalan).
- **CloudFront y S3:** con el tráfico de una demo el costo suele ser mínimo, pero no es cero.

Para estimar el costo de tu caso usa la **[AWS Pricing Calculator](https://calculator.aws/)**. Los precios cambian según la región y el momento, así que este repo no los incluye.

**Recomendaciones:**

1. **Antes de empezar**, crea una alerta en **AWS Budgets** (Billing → Budgets → *Create budget* → plantilla *Monthly cost budget*) con un monto bajo y tu email.
2. **Destruye todo al terminar** la clase o el webinar. No lo dejes corriendo "para mañana".

### Cómo destruir todo

**Si desplegaste con Terraform:**

```bash
bash scripts/infra-destroy.sh
```

El script pide escribir `destruir` para confirmar. Después ejecuta `terraform destroy`, que vacía el bucket solo (`force_destroy`) y borra todo en el orden correcto. Tarda varios minutos, porque CloudFront primero se deshabilita y luego se borra.

**Si lo creaste en la consola**, el orden importa, porque algunos recursos dependen de otros. La lista completa está en [docs/consola-aws.md → Limpieza](docs/consola-aws.md#limpieza):

1. CloudFront: *Disable* la distribución, esperar a que termine y luego *Delete*.
2. Auto Scaling Group: *Delete* (termina sus instancias).
3. Load balancer y luego el target group.
4. Launch template.
5. Bucket S3: *Empty* y luego *Delete*.
6. Security groups, rol IAM y, por último, la VPC.

Al final revisa **Billing → Bills** y **EC2 → Elastic IPs / Load balancers / Instances** en la región que usaste, para confirmar que no quedó nada.

---

## Troubleshooting

### Los targets quedan `unhealthy` en el target group

- **Security group de las instancias:** debe permitir **TCP 8080** con origen el **security group del ALB**.
- **Puerto del target group:** debe ser **8080** y el health check `/health` con *success codes* `200`.
- **La API está corriendo:** entra por **Session Manager** y ejecuta:
  ```bash
  sudo docker ps
  curl -s localhost:8080/health
  sudo tail -50 /var/log/cloud-init-output.log   # salida del user data
  ```
- **El user data todavía corre:** el primer arranque tarda unos minutos (instalación y build). Si el *health check grace period* del ASG es muy corto, el ASG mata las instancias antes de que terminen y entra en un ciclo de reemplazos. Súbelo a 300 s.
- **Las instancias no tienen salida a internet:** necesitan una IPv4 pública (auto-assign en las subredes) y una ruta a un Internet Gateway, para hacer `dnf install`, `git clone` y bajar imágenes de Docker.

### `/api/info` muestra `local-xxxx` y `local-az` en AWS

La API no puede leer IMDS desde el contenedor. En el launch template, revisa que **Metadata version = V2 only** y **Metadata response hop limit = 2**. Con hop limit 1, la respuesta de IMDS no llega al contenedor.

### Error 403 en CloudFront (el sitio no carga)

- **OAC:** el origen S3 debe usar *Origin access control* (no "Public").
- **Política del bucket:** debe permitir `s3:GetObject` al servicio `cloudfront.amazonaws.com` con la condición `AWS:SourceArn` = ARN de **tu** distribución. La consola ofrece copiarla al editar el origen.
- **Default root object:** debe ser `index.html`.
- **El bucket está vacío:** ejecuta `deploy-frontend.sh`.

### Error 504 o 502 en `/api/*`

- **Origen del ALB en CloudFront:** el protocolo debe ser **HTTP only**, puerto 80, con el DNS correcto del ALB.
- **Security group del ALB:** debe permitir el puerto 80 desde la prefix list **`com.amazonaws.global.cloudfront.origin-facing`**.
- **Listener del ALB:** HTTP:80 debe reenviar al target group.
- **Behavior `/api/*`:** debe usar *CachingDisabled*, *AllViewerExceptHostHeader* y permitir `POST`.
- **El ALB tiene targets sanos:** si no tiene ninguno, responde 503 y CloudFront lo propaga.

### El frontend no se actualiza tras desplegar

Pasa el ID de la distribución a `deploy-frontend.sh` para que invalide `/*`, y espera 1 o 2 minutos.

---

## Licencia

[MIT](LICENSE). El arte de la interfaz es original (CSS, SVG y canvas). Este es un proyecto educativo sin afiliación con ninguna serie ni marca.
