provider "aws" {
  region = var.region

  # null = usa la cadena normal de credenciales (AWS_PROFILE, variables de entorno, etc.)
  profile = var.aws_profile

  # Tags que se agregan a TODOS los recursos: facilita encontrarlos y ver costos.
  default_tags {
    tags = merge(
      {
        Project   = var.prefix
        ManagedBy = "terraform"
      },
      var.tags,
    )
  }
}
