# Los scripts (deploy-frontend.sh, demo-check.sh) leen estos valores con
# `terraform output`, así no hay que copiar nada a mano.

output "cloudfront_url" {
  description = "URL pública de la demo."
  value       = "https://${aws_cloudfront_distribution.main.domain_name}"
}

output "distribution_id" {
  description = "ID de la distribución de CloudFront (para invalidar caché)."
  value       = aws_cloudfront_distribution.main.id
}

output "bucket_name" {
  description = "Bucket S3 donde se sube el frontend."
  value       = aws_s3_bucket.web.bucket
}

output "alb_dns_name" {
  description = "DNS del ALB (no responde directo: solo acepta tráfico de CloudFront)."
  value       = aws_lb.main.dns_name
}

output "asg_name" {
  description = "Nombre del Auto Scaling Group."
  value       = "${var.prefix}-asg"
  depends_on  = [aws_iam_instance_profile.ec2]
}

output "target_group_arn" {
  description = "Target group (para ver la salud de las instancias)."
  value       = aws_lb_target_group.api.arn
}

output "region" {
  description = "Región del despliegue."
  value       = var.region
  depends_on  = [aws_iam_instance_profile.ec2]
}

output "aws_profile" {
  description = "Perfil de AWS CLI usado (vacío = credenciales por defecto)."
  value       = var.aws_profile == null ? "" : var.aws_profile
  depends_on  = [aws_iam_instance_profile.ec2]
}

# Disponibles tras crear la base, antes de construir la primera AMI/ASG.
output "builder_subnet_id" {
  value = aws_subnet.public[0].id
}
output "builder_security_group_id" {
  value = aws_security_group.app.id
}
output "builder_instance_profile" {
  value = aws_iam_instance_profile.ec2.name
}
output "api_instance_type" {
  value      = var.instance_type
  depends_on = [aws_iam_instance_profile.ec2]
}
output "api_ami_id" {
  value = var.api_ami_id == null ? "" : var.api_ami_id
}
