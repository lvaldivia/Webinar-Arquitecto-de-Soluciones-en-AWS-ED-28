# =============================================================================
# Bucket S3 PRIVADO para el frontend. Solo CloudFront puede leerlo (OAC).
# =============================================================================

resource "aws_s3_bucket" "web" {
  # Los nombres de bucket son globales: el prefijo + un sufijo aleatorio.
  bucket_prefix = "${var.prefix}-web-"

  # Permite que `terraform destroy` borre el bucket aunque tenga archivos.
  # Cómodo para una demo; en producción se deja en false.
  force_destroy = true
}

resource "aws_s3_bucket_ownership_controls" "web" {
  bucket = aws_s3_bucket.web.id

  rule {
    object_ownership = "BucketOwnerEnforced" # sin ACLs
  }
}

resource "aws_s3_bucket_public_access_block" "web" {
  bucket = aws_s3_bucket.web.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Origin Access Control: CloudFront firma sus peticiones a S3 (SigV4).
resource "aws_cloudfront_origin_access_control" "web" {
  name                              = "${var.prefix}-oac"
  description                       = "CloudFront -> S3 del frontend"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# Solo el servicio CloudFront, y solo NUESTRA distribución, puede leer objetos.
data "aws_iam_policy_document" "web_bucket" {
  statement {
    sid       = "AllowCloudFrontServicePrincipalReadOnly"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.web.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.main.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "web" {
  bucket = aws_s3_bucket.web.id
  policy = data.aws_iam_policy_document.web_bucket.json

  # La política se aplica después del bloqueo de acceso público.
  depends_on = [aws_s3_bucket_public_access_block.web]
}
