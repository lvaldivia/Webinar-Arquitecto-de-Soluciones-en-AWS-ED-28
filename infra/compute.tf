# =============================================================================
# Launch template + Auto Scaling Group + política de escalado.
# =============================================================================

# Última AMI de Amazon Linux 2023 (x86_64), publicada por AWS en SSM.
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_launch_template" "api" {
  name                   = "${var.prefix}-lt"
  image_id               = data.aws_ssm_parameter.al2023.insecure_value
  instance_type          = var.instance_type
  vpc_security_group_ids = [aws_security_group.app.id]
  update_default_version = true

  iam_instance_profile {
    arn = aws_iam_instance_profile.ec2.arn
  }

  # IMDSv2 obligatorio. hop limit 2: la API corre en un contenedor (un salto
  # de red extra); con 1 la respuesta de IMDS no llega al contenedor.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  # Monitoreo detallado: CPU cada 1 minuto (en vez de 5). Así el ASG reacciona
  # antes en el "modo estrés". Tiene un costo pequeño por instancia.
  monitoring {
    enabled = true
  }

  # Mismo flujo que scripts/user-data.sh: clonar el repo y ejecutar setup-instance.sh.
  user_data = base64encode(templatefile("${path.module}/user-data.sh.tftpl", {
    repo_url    = var.repo_url
    repo_branch = var.repo_branch
  }))

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "${var.prefix}-api" }
  }
}

resource "aws_autoscaling_group" "api" {
  name                = "${var.prefix}-asg"
  vpc_zone_identifier = aws_subnet.public[*].id # 2 AZ
  target_group_arns   = [aws_lb_target_group.api.arn]

  min_size         = 2
  desired_capacity = 2
  max_size         = 4

  # ⚠️ EL ERROR TÍPICO: el valor por defecto es "EC2", que solo revisa si la
  # MÁQUINA está encendida. Si la APP muere, el ALB deja de enviarle tráfico
  # pero el ASG nunca la reemplaza (capacidad perdida en silencio).
  # Con "ELB", el ASG usa el health check del target group y la reemplaza.
  health_check_type = "ELB"

  # Tiempo para que una instancia nueva arranque (instalar Docker, clonar y
  # construir la imagen) antes de evaluar su salud. Si es muy corto, el ASG
  # la mata antes de que termine: ciclo infinito de reemplazos.
  health_check_grace_period = 300

  # Segundos que una instancia nueva tarda en aportar métricas "normales".
  default_instance_warmup = 120

  launch_template {
    id      = aws_launch_template.api.id
    version = aws_launch_template.api.latest_version
  }

  # Si cambia el launch template (p. ej. otro repo_url), reemplaza las
  # instancias de a poco sin cortar el servicio.
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
  }

  # Métricas del grupo en CloudWatch (pestaña Monitoring del ASG).
  enabled_metrics = [
    "GroupDesiredCapacity",
    "GroupInServiceInstances",
    "GroupPendingInstances",
    "GroupTerminatingInstances",
  ]

  tag {
    key                 = "Name"
    value               = "${var.prefix}-api"
    propagate_at_launch = true
  }

  lifecycle {
    # La política de escalado cambia desired_capacity; Terraform no debe "deshacerlo".
    ignore_changes = [desired_capacity]
  }
}

# Target tracking: el ASG agrega o quita instancias para mantener la CPU
# promedio del grupo cerca del 50 %.
resource "aws_autoscaling_policy" "cpu" {
  name                   = "${var.prefix}-cpu-50"
  autoscaling_group_name = aws_autoscaling_group.api.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 50
  }
}
