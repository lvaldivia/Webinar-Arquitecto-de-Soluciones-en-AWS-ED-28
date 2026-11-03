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
  value       = aws_autoscaling_group.api.name
}

output "target_group_arn" {
  description = "Target group (para ver la salud de las instancias)."
  value       = aws_lb_target_group.api.arn
}

output "region" {
  description = "Región del despliegue."
  value       = var.region
}

output "aws_profile" {
  description = "Perfil de AWS CLI usado (vacío = credenciales por defecto)."
  value       = var.aws_profile == null ? "" : var.aws_profile
}
