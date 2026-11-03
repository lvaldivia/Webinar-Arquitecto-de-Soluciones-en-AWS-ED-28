# Observar la demo en la consola de AWS

Despliega con `bash scripts/infra-up.sh`. El flujo construye una AMI y configura las EC2 sin user data; los scripts de instalación del modo anterior se retiraron.

1. **EC2 → AMIs:** localiza la imagen que imprime `build-api-ami.sh`. Incluye Docker, dependencias, API y configuración del contenedor. Conserva también sus snapshots mientras uses esa AMI.
2. **EC2 → Launch templates:** comprueba la AMI y versión elegidas por el grupo. User data debe estar vacío. IMDSv2 es obligatorio, con hop limit 2 para acceder desde el contenedor.
3. **EC2 → Auto Scaling Groups:** mínimo 2, deseadas inicialmente 2, máximo 4; health checks ELB, gracia 120 s y warmup 60 s.
4. **Automatic scaling / CloudWatch:** la alarma de ampliación usa `Grimorios/Demo`, CPUUtilization, dimensión AutoScalingGroupName, promedio >60 %, período 10 s y 1 de 1 puntos. Añade una EC2. La alarma de reducción usa CPU nativa de EC2 <10 % durante 5 períodos de 60 s.
5. **Activity:** observa las razones y horas de lanzamiento. **Instance refresh** muestra la renovación al desplegar otra AMI.
6. **Target groups → Targets:** el ALB comprueba `/health` cada 5 s. Una EC2 no debe presentarse como lista hasta que el target sea healthy. El panel C muestra este estado real.
7. **CloudFront:** `/api/*` se reenvía al ALB sin caché; el resto del contenido se sirve desde S3 privado con OAC. El navegador usa el mismo dominio para ambos.
8. **Systems Manager → Session Manager:** permite revisar Docker y logs sin abrir SSH. `docker ps` muestra el contenedor y `docker logs grimorio-api` sus registros.

## Prueba en clase

Abre la URL de CloudFront. En el panel C deja 300 s y pulsa hasta cargar ambas instancias por encima del 60 % promedio. Observa “Desplegando…” y luego “Lista para atender”. El objetivo es alrededor de un minuto; el tiempo real depende de AWS. La cuarta instancia requiere mantener suficiente carga después de incorporar la tercera.

## Limpieza

`bash scripts/infra-destroy.sh` elimina los recursos de Terraform tras confirmar. Después revisa EC2 → AMIs y Snapshots para borrar las imágenes del constructor que ya no uses. El estado y las configuraciones locales no se suben al repo.
