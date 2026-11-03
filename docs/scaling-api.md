# Estado del escalado de la demo

`GET /api/scaling` es una consulta de solo lectura. En AWS responde `200` con:

```json
{"status":"ok","desired":3,"minimum":2,"maximum":4,"ready":2,"deploying":1,"instances":[{"instance_id":"i-ejemplo","availability_zone":"us-east-1a","state":"deploying"}]}
```

`instances` enumera todas las EC2 del grupo. `state` puede ser `deploying`, `ready` o `terminating`. Una EC2 solo es `ready` cuando está `InService` y su target del ALB está `healthy`. `deploying` incluye plazas solicitadas que aún no tienen ID de instancia. El resultado se conserva hasta 3 segundos por servidor; el frontend consulta cada 3 segundos tras completar la petición anterior.

Sin `AUTOSCALING_GROUP_NAME`, responde `200` con `{"status":"disabled","instances":[]}`. Si AWS falla, responde `503` con `{"status":"unavailable","instances":[]}`. El panel muestra que perdió la conexión; no presenta datos antiguos como actuales. Los health checks no dependen de esta consulta.

La API publica la CPU media de cada ventana de 10 segundos como `Grimorios/Demo / CPUUtilization`, resolución 1 segundo y dimensión `AutoScalingGroupName`. La alarma usa promedio >60 %, 1 de 1 períodos de 10 s. Durante los primeros 20 s se omite el pico de arranque. El scale-in conserva la señal nativa de EC2 (<10 % durante cinco minutos). Estas métricas y alarmas de alta resolución generan cargos adicionales de CloudWatch.

La aplicación puede publicar esa métrica y leer ASG/targets con su rol IAM. No puede crear instancias ni modificar la capacidad: el lanzamiento lo decide la política del Auto Scaling Group a partir de CPU real.

## Detener el estrés

El estrés termina automáticamente al cumplirse su duración. `POST /api/stress/stop`, sin body, permite cancelarlo antes en la instancia que recibe la petición. Es idempotente: responde `200` con `{"status":"stopped","remaining_seconds":0,"instance_id":"i-ejemplo","availability_zone":"us-east-1a"}` aunque ya estuviera parada. Si los procesos siguen terminando, responde `202` con `status: "stopping"`; un nuevo estrés se rechaza hasta que finalicen.

El botón Parar estrés envía peticiones por el ALB y confirma los IDs de las instancias que respondieron `stopped`, hasta cubrir las instancias activas observadas. Si falta alguna confirmación, informa de la parada parcial y permite reintentar. Las instancias retiradas durante la operación ya no se consideran pendientes. Detener CPU no cambia directamente la capacidad deseada: las políticas de AWS siguen controlando el scale-in.
