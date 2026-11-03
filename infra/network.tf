# =============================================================================
# Red: VPC con 2 subredes públicas en 2 zonas de disponibilidad (Multi-AZ).
# =============================================================================

# Las 2 primeras AZ disponibles de la región (p. ej. us-east-1a y us-east-1b).
data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.prefix}-vpc" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "${var.prefix}-igw" }
}

# Una subred pública por AZ: 10.0.0.0/24 y 10.0.1.0/24.
resource "aws_subnet" "public" {
  count = length(local.azs)

  vpc_id            = aws_vpc.main.id
  availability_zone = local.azs[count.index]
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index)

  # Las instancias reciben IP pública para salir a internet (dnf, git, Docker Hub).
  # Ojo: tener IP pública NO las expone; su security group solo acepta al ALB.
  map_public_ip_on_launch = true

  tags = { Name = "${var.prefix}-public-${local.azs[count.index]}" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "${var.prefix}-public-rt" }
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# -----------------------------------------------------------------------------
# Versión de producción (NO usada en la demo, por costo):
#
#   - 2 subredes PRIVADAS (una por AZ) para las instancias, sin IP pública.
#   - 1 NAT Gateway por AZ en las subredes públicas, para que las instancias
#     privadas salgan a internet.
#   - El ALB sigue en las subredes públicas.
#
# resource "aws_subnet" "private" {
#   count             = length(local.azs)
#   vpc_id            = aws_vpc.main.id
#   availability_zone = local.azs[count.index]
#   cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 10)
# }
#
# resource "aws_eip" "nat" {
#   count  = length(local.azs)
#   domain = "vpc"
# }
#
# resource "aws_nat_gateway" "main" {
#   count         = length(local.azs)
#   allocation_id = aws_eip.nat[count.index].id
#   subnet_id     = aws_subnet.public[count.index].id
# }
#
# resource "aws_route_table" "private" {
#   count  = length(local.azs)
#   vpc_id = aws_vpc.main.id
#   route {
#     cidr_block     = "0.0.0.0/0"
#     nat_gateway_id = aws_nat_gateway.main[count.index].id
#   }
# }
#
# Y en el ASG: vpc_zone_identifier = aws_subnet.private[*].id
#
# ¿Por qué no? Cada NAT Gateway se cobra por hora + por GB procesado. Con uno
# por AZ, en una demo corta puede costar más que todo lo demás junto.
# -----------------------------------------------------------------------------
