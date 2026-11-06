resource "aws_vpc" "asistencia" {
  cidr_block           = "10.42.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "asistencia" }
}

resource "aws_subnet" "publica" {
  vpc_id     = aws_vpc.asistencia.id
  cidr_block = "10.42.1.0/24"

  tags = { Name = "asistencia-publica" }
}

resource "aws_internet_gateway" "asistencia" {
  vpc_id = aws_vpc.asistencia.id

  tags = { Name = "asistencia" }
}

resource "aws_route_table" "publica" {
  vpc_id = aws_vpc.asistencia.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.asistencia.id
  }

  tags = { Name = "asistencia-publica" }
}

resource "aws_route_table_association" "publica" {
  subnet_id      = aws_subnet.publica.id
  route_table_id = aws_route_table.publica.id
}

resource "aws_security_group" "instancia" {
  for_each = toset(["cliente", "backend"])

  name        = "asistencia-${each.key}"
  description = "Acceso de red para el rol ${each.key}"
  vpc_id      = aws_vpc.asistencia.id
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  for_each = aws_security_group.instancia

  security_group_id = each.value.id
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_ipv4         = var.ssh_cidr
}

resource "aws_vpc_security_group_ingress_rule" "http" {
  security_group_id = aws_security_group.instancia["cliente"].id
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "api" {
  security_group_id            = aws_security_group.instancia["backend"].id
  referenced_security_group_id = aws_security_group.instancia["cliente"].id
  ip_protocol                  = "tcp"
  from_port                    = 8090
  to_port                      = 8090
}

resource "aws_vpc_security_group_egress_rule" "salida" {
  for_each = aws_security_group.instancia

  security_group_id = each.value.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
