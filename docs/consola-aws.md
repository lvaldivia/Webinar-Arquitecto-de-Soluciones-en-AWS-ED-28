# Guía paso a paso en la consola de AWS

Esta guía crea toda la arquitectura **a mano**, en la región **us-east-1** (Norte de Virginia). Se puede usar otra región, siempre que se use la misma en todos los pasos.

Usa un **prefijo** común para nombrar los recursos, así es fácil encontrarlos y borrarlos. En la guía el prefijo es `grimorios`.

> Los nombres de botones pueden cambiar un poco entre versiones de la consola. Si no encuentras uno exacto, busca la opción equivalente.

## Índice

0. [Alerta de costos](#0-alerta-de-costos)
1. [VPC](#1-vpc)
2. [Security groups](#2-security-groups)
3. [Rol IAM de las instancias](#3-rol-iam-de-las-instancias)
4. [Launch template](#4-launch-template)
5. [Target group](#5-target-group)
6. [Application Load Balancer](#6-application-load-balancer)
7. [Auto Scaling Group](#7-auto-scaling-group)
8. [Bucket S3 del frontend](#8-bucket-s3-del-frontend)
9. [Distribución de CloudFront](#9-distribución-de-cloudfront)
10. [Desplegar el frontend](#10-desplegar-el-frontend)
11. [Limpieza](#limpieza)

---

## 0. Alerta de costos

**Billing and Cost Management → Budgets → Create budget**

- Plantilla: **Monthly cost budget**
- Monto: uno bajo (el que estés dispuesto a gastar)
- Email: el tuyo

## 1. VPC

**VPC → Create VPC → VPC and more**

| Campo | Valor |
|---|---|
| Name tag auto-generation | `grimorios` |
| IPv4 CIDR | `10.0.0.0/16` |
| Number of Availability Zones | **2** |
| Number of public subnets | **2** |
| Number of private subnets | **0** |
| NAT gateways | **None** |
| VPC endpoints | **None** |

Después, en **VPC → Subnets**, para **cada** subred pública: **Actions → Edit subnet settings → ✅ Enable auto-assign public IPv4 address**.

> **¿Por qué subredes públicas?** Las instancias necesitan internet para instalar Docker, clonar el repo y bajar imágenes. Lo "correcto" en producción es ponerlas en **subredes privadas** con un **NAT Gateway**. Pero el NAT Gateway se cobra por hora y por GB, y lo ideal sería uno por AZ, así que para una demo encarece bastante. Aquí las instancias tienen IP pública, pero **nadie puede llegarles directamente**: su security group solo acepta tráfico desde el ALB. Más detalles en [arquitectura.md](arquitectura.md#subredes-públicas-vs-privadas).

## 2. Security groups

**EC2 → Security Groups → Create security group**. Crea dos, ambos en la VPC `grimorios-vpc`.

### `grimorios-alb-sg` (para el balanceador)

| Inbound | Puerto | Origen |
|---|---|---|
| HTTP | 80 | **Prefix list** → `com.amazonaws.global.cloudfront.origin-facing` |

Deja el outbound por defecto (todo permitido).

> Esta prefix list administrada por AWS contiene las IP que CloudFront usa para conectarse a los orígenes. Así el ALB **no acepta tráfico directo de internet**: solo de CloudFront.
> Ten en cuenta que esa regla "pesa" varias reglas en la cuota del security group. Si la consola se queja, solicita un aumento de cuota de reglas por security group.

### `grimorios-app-sg` (para las instancias)

| Inbound | Puerto | Origen |
|---|---|---|
| Custom TCP | **8080** | **Security group** → `grimorios-alb-sg` |

No agregues SSH (22): entraremos con **Session Manager**.

## 3. Rol IAM de las instancias

**IAM → Roles → Create role**

- Trusted entity: **AWS service → EC2**
- Permisos: **`AmazonSSMManagedInstanceCore`** (y nada más)
- Nombre: `grimorios-ec2-role`

Con esto puedes entrar a cualquier instancia desde **EC2 → Instances → Connect → Session Manager**, sin llaves SSH ni puerto 22 abierto.

<details>
<summary><strong>Opcional:</strong> publicar el frontend desde una instancia</summary>

Si quieres ejecutar `deploy-frontend.sh` dentro de una EC2, agrega al rol una política inline como esta. Reemplaza `NOMBRE-DEL-BUCKET`, `ID-DE-CUENTA` e `ID-DE-DISTRIBUCION` por tus valores.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ListarBucket",
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::NOMBRE-DEL-BUCKET"
    },
    {
      "Sid": "EscribirObjetos",
      "Effect": "Allow",
      "Action": ["s3:PutObject", "s3:DeleteObject"],
      "Resource": "arn:aws:s3:::NOMBRE-DEL-BUCKET/*"
    },
    {
      "Sid": "InvalidarCloudFront",
      "Effect": "Allow",
      "Action": "cloudfront:CreateInvalidation",
      "Resource": "arn:aws:cloudfront::ID-DE-CUENTA:distribution/ID-DE-DISTRIBUCION"
    }
  ]
}
```

Recuerda que **todas** las instancias del ASG tendrían este permiso. Para una demo es aceptable. En producción, el despliegue se haría desde un pipeline de CI/CD con su propio rol.

</details>

## 4. Launch template

**EC2 → Launch templates → Create launch template**

| Campo | Valor |
|---|---|
| Name | `grimorios-lt` |
| Auto Scaling guidance | ✅ marcado |
| AMI | **Amazon Linux 2023** (x86_64) |
| Instance type | `t3.micro` o `t3.small` |
| Key pair | **Don't include** (usamos Session Manager) |
| Network settings → Subnet | **Don't include** (lo decide el ASG) |
| Network settings → Security groups | `grimorios-app-sg` |

En **Advanced details**:

| Campo | Valor |
|---|---|
| IAM instance profile | `grimorios-ec2-role` |
| Metadata accessible | **Enabled** |
| Metadata version | **V2 only (token required)** |
| Metadata response hop limit | **2** |
| User data | contenido de [`scripts/user-data.sh`](../scripts/user-data.sh), **con tu `REPO_URL`** |

> **¿Por qué hop limit 2?** La API corre dentro de un contenedor, así que la respuesta de IMDS hace un salto extra (host → contenedor). Con el valor por defecto (1), el token de IMDSv2 nunca llega al contenedor, y la API mostraría `local-xxxx` en vez del `instance_id` real.

## 5. Target group

**EC2 → Target groups → Create target group**

| Campo | Valor |
|---|---|
| Target type | **Instances** |
| Name | `grimorios-tg` |
| Protocol / Port | **HTTP / 8080** |
| VPC | `grimorios-vpc` |
| Health check path | **`/health`** |
| Advanced → Healthy threshold | 2 |
| Advanced → Unhealthy threshold | 2 |
| Advanced → Interval | 10 s |
| Advanced → Success codes | **200** |

No registres targets: el ASG lo hará solo.

Cuando esté creado, ve a **Attributes → Edit → Deregistration delay** y bájalo a **30 s**. El valor por defecto es 300 s, y para la demo conviene ver más rápido cómo sale una instancia.

## 6. Application Load Balancer

**EC2 → Load balancers → Create → Application Load Balancer**

| Campo | Valor |
|---|---|
| Name | `grimorios-alb` |
| Scheme | **Internet-facing** |
| IP address type | IPv4 |
| VPC | `grimorios-vpc` |
| Mappings | ✅ las **2 AZ**, cada una con su subred pública |
| Security groups | **solo** `grimorios-alb-sg` (quita el `default`) |
| Listener | **HTTP : 80** → Forward to `grimorios-tg` |

Copia el **DNS name** del ALB (por ejemplo `grimorios-alb-123456.us-east-1.elb.amazonaws.com`): lo usarás en CloudFront.

> Si abres ese DNS en el navegador, **no responde**. Es lo esperado: el ALB solo acepta tráfico de CloudFront.

## 7. Auto Scaling Group

**EC2 → Auto Scaling Groups → Create Auto Scaling group**

**Paso 1, Launch template:** `grimorios-lt` (versión *Latest*). Nombre: `grimorios-asg`.

**Paso 2, Network:** VPC `grimorios-vpc`, y las **2 subredes públicas** (una por AZ).

**Paso 3, Load balancing y health checks:**

| Campo | Valor |
|---|---|
| Load balancing | **Attach to an existing load balancer** → `grimorios-tg` |
| **Turn on Elastic Load Balancing health checks** | ✅ **marcado** |
| Health check grace period | **300** segundos |

> 🎯 **El error típico (tema del webinar):** por defecto el ASG usa health checks de tipo **EC2**, que solo revisan si la *máquina* está encendida. Si la aplicación muere pero la instancia sigue corriendo, el ALB la marca `unhealthy` y deja de enviarle tráfico, pero **el ASG nunca la reemplaza**, y te quedas con menos capacidad sin enterarte. Con **ELB health checks** activado, el ASG también usa el resultado del target group y reemplaza la instancia.
>
> El **grace period** le da tiempo a una instancia nueva para arrancar: instalar Docker, clonar el repo y construir la imagen. Si es muy corto, el ASG la mata antes de que termine y entra en un ciclo infinito de reemplazos.

**Paso 4, Group size y scaling:**

| Campo | Valor |
|---|---|
| Desired capacity | **2** |
| Min | **2** |
| Max | **4** |
| Automatic scaling | **Target tracking scaling policy** |
| Metric type | **Average CPU utilization** |
| Target value | **50** |
| Instance warmup | 120 s |

Marca **Enable group metrics collection within CloudWatch** (si aparece), para ver las gráficas en la pestaña *Monitoring*.

**Tags (opcional):** `Name = grimorios-api`, para reconocer las instancias en la lista.

Crea el grupo y ve a **Activity**: verás el lanzamiento de 2 instancias. A los 3 a 5 minutos, en **Target groups → grimorios-tg → Targets**, deberían aparecer las 2 como **healthy**.

## 8. Bucket S3 del frontend

**S3 → Create bucket**

| Campo | Valor |
|---|---|
| Bucket type | General purpose |
| Name | `grimorios-web-<algo-único>` (los nombres son globales) |
| Region | la misma que usas en todo |
| Object Ownership | ACLs disabled |
| **Block all public access** | ✅ **marcado** (el bucket es privado) |

**No** actives "Static website hosting": CloudFront lee los objetos con OAC directamente.

## 9. Distribución de CloudFront

**CloudFront → Create distribution**

> La consola de CloudFront cambia seguido de diseño. Lo importante son los valores, no el orden de las pantallas. Si te ofrece elegir un plan, el de pago por uso (*pay-as-you-go*) sirve. **No actives WAF** para la demo, porque tiene costo propio.

### Origen 1 (por defecto): S3

| Campo | Valor |
|---|---|
| Origin domain | tu bucket `grimorios-web-…` (el que termina en `.s3.<region>.amazonaws.com`) |
| Origin access | **Origin access control settings (recommended)** → *Create new OAC* (firmar requests) |
| Default root object | **`index.html`** |

Behavior por defecto (`*`):

| Campo | Valor |
|---|---|
| Viewer protocol policy | **Redirect HTTP to HTTPS** |
| Allowed methods | GET, HEAD |
| Cache policy | **CachingOptimized** |

Al crear la distribución, CloudFront muestra un aviso con la **política del bucket** que necesita. Cópiala y pégala en **S3 → tu bucket → Permissions → Bucket policy** (o deja que la consola la aplique, si te lo ofrece). Se ve así:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowCloudFrontServicePrincipalReadOnly",
      "Effect": "Allow",
      "Principal": { "Service": "cloudfront.amazonaws.com" },
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::NOMBRE-DEL-BUCKET/*",
      "Condition": {
        "StringEquals": {
          "AWS:SourceArn": "arn:aws:cloudfront::ID-DE-CUENTA:distribution/ID-DE-DISTRIBUCION"
        }
      }
    }
  ]
}
```

### Origen 2: el ALB

**Tu distribución → Origins → Create origin**

| Campo | Valor |
|---|---|
| Origin domain | el **DNS del ALB** |
| Protocol | **HTTP only**, puerto **80** |
| Name | `grimorios-alb` |

### Behavior `/api/*`

**Behaviors → Create behavior**

| Campo | Valor |
|---|---|
| Path pattern | **`/api/*`** |
| Origin | `grimorios-alb` |
| Viewer protocol policy | Redirect HTTP to HTTPS |
| Allowed methods | **GET, HEAD, OPTIONS, PUT, POST, PATCH, DELETE** |
| Cache policy | **CachingDisabled** |
| Origin request policy | **AllViewerExceptHostHeader** |

> **¿Por qué *except Host*?** CloudFront reenvía todo lo que mandó el navegador (headers, cookies, query strings), excepto el header `Host`. Si reenviara `Host: dxxxx.cloudfront.net`, el ALB recibiría un nombre que no es el suyo. Sin el header, CloudFront usa el DNS del ALB.

### Páginas de error (SPA)

**Error pages → Create custom error response**, dos veces:

| HTTP error code | Customize response | Response page path | HTTP response code |
|---|---|---|---|
| **403** | Yes | `/index.html` | **200** |
| **404** | Yes | `/index.html` | **200** |

> S3 con OAC responde **403** (no 404) cuando un archivo no existe. Por eso se capturan ambos códigos y se devuelve la app. Ojo: estas respuestas aplican a **toda** la distribución, incluido `/api/*`. Esta API no devuelve 403/404 en uso normal, pero en un proyecto real hay que tenerlo en cuenta.

Espera a que la distribución termine de desplegarse: la columna *Last modified* deja de decir *Deploying*. **Puede tardar varios minutos.**

## 10. Desplegar el frontend

Desde tu laptop (con AWS CLI configurado) o desde una instancia con el permiso opcional del paso 3:

```bash
bash scripts/deploy-frontend.sh grimorios-web-<algo-único> <ID-DE-DISTRIBUCION>
```

Abre `https://dxxxxxxxxxxxxx.cloudfront.net` y verifica con:

```bash
bash scripts/demo-check.sh https://dxxxxxxxxxxxxx.cloudfront.net
```

---

## Limpieza

Borra en este orden. Algunos recursos no se pueden borrar mientras otro los use.

| # | Recurso | Dónde | Nota |
|---|---|---|---|
| 1 | Distribución CloudFront | CloudFront → *Disable* → esperar → *Delete* | El *Disable* tarda unos minutos |
| 2 | OAC | CloudFront → Origin access | Después de borrar la distribución |
| 3 | Auto Scaling Group | EC2 → Auto Scaling Groups → *Delete* | Termina sus instancias |
| 4 | Load balancer | EC2 → Load balancers → *Delete* | Se cobra por hora: no lo olvides |
| 5 | Target group | EC2 → Target groups → *Delete* | |
| 6 | Launch template | EC2 → Launch templates → *Delete* | |
| 7 | Bucket S3 | S3 → *Empty* → *Delete* | |
| 8 | Security groups | EC2 → Security Groups | Primero `app-sg`, después `alb-sg` |
| 9 | Rol IAM | IAM → Roles → `grimorios-ec2-role` | |
| 10 | VPC | VPC → Your VPCs → *Delete VPC* | Borra subredes, IGW y tablas de rutas |
| 11 | Budget (opcional) | Billing → Budgets | Puedes dejarlo para el futuro |

Para terminar, revisa en **EC2** (Instances, Load balancers, Elastic IPs) y en **Billing → Bills** que no quedó nada cobrando en la región.
