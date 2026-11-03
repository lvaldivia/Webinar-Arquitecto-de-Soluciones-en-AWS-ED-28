terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.71"
    }
  }

  # Estado local (archivo terraform.tfstate en esta carpeta): lo más simple
  # para una demo. En equipos se usa un backend remoto (S3) para compartirlo.
}
