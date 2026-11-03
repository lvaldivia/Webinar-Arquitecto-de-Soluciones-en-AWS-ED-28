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

variable "instance_type" {
  description = "Tipo de instancia de la API."
  type        = string
  default     = "t3.micro"
}

variable "api_ami_id" {
  description = "AMI con Docker y grimorio-api. El constructor guarda su ID en api-ami.auto.tfvars.json."
  type        = string
  default     = null

  validation {
    condition     = var.api_ami_id == null ? true : can(regex("^ami-[0-9a-f]+$", var.api_ami_id))
    error_message = "api_ami_id debe ser un ID de AMI válido o null."
  }
}

variable "vpc_cidr" {
  description = "Rango de IPs de la VPC."
  type        = string
  default     = "10.0.0.0/16"
}
