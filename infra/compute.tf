# =============================================================================
# Launch template + Auto Scaling Group + política de escalado.
# =============================================================================

resource "aws_launch_template" "api" {
  name                   = "${var.prefix}-lt"
  image_id               = var.api_ami_id
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

  # Sin user data: Docker arranca el contenedor ya preparado dentro de la AMI.

  lifecycle {
    precondition {
      condition     = var.api_ami_id != null
      error_message = "Primero construye la AMI con bash scripts/infra-up.sh o bash scripts/build-api-ami.sh."
    }
  }

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

  # Gracia para arrancar el sistema y el contenedor antes de evaluar su salud.
  health_check_grace_period = 120

  # Segundos que una instancia nueva tarda en aportar métricas "normales".
  default_instance_warmup = 60

  launch_template {
    id      = aws_launch_template.api.id
    version = aws_launch_template.api.latest_version
  }

  # Si cambia el launch template (p. ej. otra AMI), reemplaza las
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

# Demo: una muestra de 10 segundos por encima del 60 % agrega una EC2.
# El warmup evita sumar instancias repetidamente mientras la nueva arranca.
resource "aws_autoscaling_policy" "cpu" {
  name                      = "${var.prefix}-cpu-demo-out"
  autoscaling_group_name    = aws_autoscaling_group.api.name
  policy_type               = "StepScaling"
  adjustment_type           = "ChangeInCapacity"
  metric_aggregation_type   = "Average"
  estimated_instance_warmup = 60

  step_adjustment {
    metric_interval_lower_bound = 0
    scaling_adjustment          = 1
  }
}

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${var.prefix}-cpu-demo-high"
  alarm_description   = "Demo: CPU promedio >60 % durante 10 segundos; agregar una EC2."
  namespace           = "Grimorios/Demo"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 10
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  threshold           = 60
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  dimensions          = { AutoScalingGroupName = aws_autoscaling_group.api.name }
  alarm_actions       = [aws_autoscaling_policy.cpu.arn]
}

# Retirar una instancia solo después de cinco minutos de poca carga.
resource "aws_autoscaling_policy" "cpu_in" {
  name                    = "${var.prefix}-cpu-demo-in"
  autoscaling_group_name  = aws_autoscaling_group.api.name
  policy_type             = "StepScaling"
  adjustment_type         = "ChangeInCapacity"
  metric_aggregation_type = "Average"

  step_adjustment {
    metric_interval_upper_bound = 0
    scaling_adjustment          = -1
  }
}

resource "aws_cloudwatch_metric_alarm" "cpu_low" {
  alarm_name          = "${var.prefix}-cpu-demo-low"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 5
  datapoints_to_alarm = 5
  threshold           = 10
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "notBreaching"
  dimensions          = { AutoScalingGroupName = aws_autoscaling_group.api.name }
  alarm_actions       = [aws_autoscaling_policy.cpu_in.arn]
}
