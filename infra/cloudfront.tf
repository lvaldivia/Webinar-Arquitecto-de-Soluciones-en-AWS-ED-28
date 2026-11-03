# =============================================================================
# CloudFront: un solo dominio para todo.
#   default (*) -> S3 (frontend, cacheado)
#   /api/*      -> ALB (API, sin caché)
# =============================================================================

# Políticas administradas por AWS.
data "aws_cloudfront_cache_policy" "optimized" {
  name = "Managed-CachingOptimized"
}

data "aws_cloudfront_cache_policy" "disabled" {
  name = "Managed-CachingDisabled"
}

# Reenvía al ALB headers, cookies y query strings del navegador, MENOS "Host"
# (el ALB debe recibir su propio nombre, no dxxxx.cloudfront.net).
data "aws_cloudfront_origin_request_policy" "all_except_host" {
  name = "Managed-AllViewerExceptHostHeader"
}

locals {
  s3_origin_id  = "s3-frontend"
  alb_origin_id = "alb-api"
}

resource "aws_cloudfront_distribution" "main" {
  enabled             = true
  comment             = "${var.prefix}: frontend (S3) + API (ALB)"
  default_root_object = "index.html"
  is_ipv6_enabled     = true

  # Solo edges de Norteamérica y Europa: más barato. Para la demo alcanza.
  price_class = "PriceClass_100"

  # ---------- Origen 1: S3 privado vía OAC ----------
  origin {
    origin_id                = local.s3_origin_id
    domain_name              = aws_s3_bucket.web.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.web.id
  }

  # ---------- Origen 2: ALB ----------
  origin {
    origin_id   = local.alb_origin_id
    domain_name = aws_lb.main.dns_name

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only" # demo: HTTP entre CloudFront y el ALB
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # ---------- Behavior por defecto: el frontend (cacheado) ----------
  default_cache_behavior {
    target_origin_id       = local.s3_origin_id
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = data.aws_cloudfront_cache_policy.optimized.id
    compress               = true
  }

  # ---------- Behavior /api/*: la API (nunca se cachea) ----------
  ordered_cache_behavior {
    path_pattern             = "/api/*"
    target_origin_id         = local.alb_origin_id
    viewer_protocol_policy   = "redirect-to-https"
    allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods           = ["GET", "HEAD"]
    cache_policy_id          = data.aws_cloudfront_cache_policy.disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_except_host.id
  }

  # ---------- SPA: rutas desconocidas devuelven la app ----------
  # Con OAC, S3 responde 403 (no 404) si el archivo no existe.
  # Nota: aplica a toda la distribución, incluido /api/*.
  custom_error_response {
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 10
  }

  custom_error_response {
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 10
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # HTTPS con el certificado *.cloudfront.net (en producción: dominio propio + ACM).
  viewer_certificate {
    cloudfront_default_certificate = true
  }
}
