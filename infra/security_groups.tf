# =============================================================================
# Security groups encadenados:
#   CloudFront ──80──► ALB ──8080──► instancias
# Nadie más puede hablar con el ALB ni con las instancias.
# =============================================================================

# Lista administrada por AWS con las IPs que CloudFront usa para llegar a los orígenes.
data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

# ---------- ALB ----------
resource "aws_security_group" "alb" {
  name        = "${var.prefix}-alb-sg"
  description = "ALB: solo acepta HTTP desde CloudFront"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${var.prefix}-alb-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "alb_from_cloudfront" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTP desde CloudFront"
  prefix_list_id    = data.aws_ec2_managed_prefix_list.cloudfront.id
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

resource "aws_vpc_security_group_egress_rule" "alb_all" {
  security_group_id = aws_security_group.alb.id
  description       = "Salida hacia las instancias"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# ---------- Instancias ----------
resource "aws_security_group" "app" {
  name        = "${var.prefix}-app-sg"
  description = "Instancias: solo aceptan 8080 desde el ALB (sin SSH)"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${var.prefix}-app-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "app_from_alb" {
  security_group_id = aws_security_group.app.id
  description       = "API desde el ALB"
  # Origen = el security group del ALB (no un rango de IPs).
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080
}

resource "aws_vpc_security_group_egress_rule" "app_all" {
  security_group_id = aws_security_group.app.id
  description       = "Salida a internet (dnf, git, Docker Hub, SSM)"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
