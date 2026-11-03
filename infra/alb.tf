# =============================================================================
# Application Load Balancer + target group con health check.
# =============================================================================

resource "aws_lb" "main" {
  name               = "${var.prefix}-alb"
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id # en las 2 AZ
}

resource "aws_lb_target_group" "api" {
  name     = "${var.prefix}-tg"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  # Al sacar una instancia, espera 30 s (en vez de 300) a que terminen sus requests.
  # Más corto = en la demo se ve más rápido cómo sale una instancia.
  deregistration_delay = 30

  health_check {
    path                = "/health" # endpoint liviano, sin dependencias externas
    matcher             = "200"
    interval            = 5
    timeout             = 2
    healthy_threshold   = 2
    unhealthy_threshold = 2 # comprobación rápida para la demo
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }
}
