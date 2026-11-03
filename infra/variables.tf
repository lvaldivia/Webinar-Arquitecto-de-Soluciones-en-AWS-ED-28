variable "region" {
  description = "Región de AWS donde se despliega todo."
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "Perfil de AWS CLI a usar (null = credenciales por defecto)."
  type        = string
  default     = null
}

variable "prefix" {
  description = "Prefijo para los nombres de los recursos."
  type        = string
  default     = "grimorios"
}

variable "tags" {
  description = "Tags extra para todos los recursos."
  type        = map(string)
  default     = {}
}

variable "repo_url" {
  description = "URL HTTPS del repo PÚBLICO que clonan las instancias al arrancar."
  type        = string

  validation {
    condition     = startswith(var.repo_url, "https://") && !strcontains(var.repo_url, "TU-USUARIO")
    error_message = "repo_url debe ser la URL https de TU repo público (p. ej. https://github.com/usuario/repo.git)."
  }
}

variable "repo_branch" {
  description = "Rama del repo que se despliega."
  type        = string
  default     = "main"
}

variable "instance_type" {
  description = "Tipo de instancia de la API."
  type        = string
  default     = "t3.micro"
}

variable "vpc_cidr" {
  description = "Rango de IPs de la VPC."
  type        = string
  default     = "10.0.0.0/16"
}
