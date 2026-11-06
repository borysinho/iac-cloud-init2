data "aws_ssm_parameter" "ubuntu" {
  name = "/aws/service/canonical/ubuntu/server/noble/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

data "aws_key_pair" "globomatics" {
  key_name = "globomatics"
}

locals {
  cloud_init  = replace(file("${path.module}/../cloud-init.yaml"), "__REGION_APP__", var.region)
  app_package = "${path.module}/.asistencia/app.tar.gz"
  app_url     = "s3://${aws_s3_object.app.bucket}/${aws_s3_object.app.key}"
}

resource "aws_s3_object" "app" {
  bucket                 = var.state_bucket
  key                    = "cloud-init-2/opentofu/app/${filesha256(local.app_package)}.tar.gz"
  source                 = local.app_package
  content_type           = "application/gzip"
  server_side_encryption = "AES256"
}

resource "aws_iam_role" "descarga" {
  name_prefix = "asistencia-descarga-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "descarga" {
  name = "descarga-paquete"
  role = aws_iam_role.descarga.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "s3:GetObject"
      Resource = aws_s3_object.app.arn
    }]
  })
}

resource "aws_iam_instance_profile" "descarga" {
  name_prefix = "asistencia-descarga-"
  role        = aws_iam_role.descarga.name
}

resource "aws_instance" "cliente" {
  ami                         = nonsensitive(data.aws_ssm_parameter.ubuntu.value)
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.publica.id
  private_ip                  = "10.42.1.10"
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.instancia["cliente"].id]
  key_name                    = data.aws_key_pair.globomatics.key_name
  iam_instance_profile        = aws_iam_instance_profile.descarga.name
  user_data                   = replace(replace(local.cloud_init, "__ROL__", "cliente"), "__URL_APP__", local.app_url)
  user_data_replace_on_change = true

  credit_specification {
    cpu_credits = "standard"
  }

  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    encrypted = true
  }

  # La salida a Internet debe estar lista cuando arranque cloud-init.
  depends_on = [aws_route_table_association.publica, aws_vpc_security_group_egress_rule.salida, aws_iam_role_policy.descarga]

  tags = { Name = "asistencia-cliente" }
}

resource "aws_instance" "backend" {
  ami                         = nonsensitive(data.aws_ssm_parameter.ubuntu.value)
  instance_type               = "t3.small"
  subnet_id                   = aws_subnet.publica.id
  private_ip                  = "10.42.1.20"
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.instancia["backend"].id]
  key_name                    = data.aws_key_pair.globomatics.key_name
  iam_instance_profile        = aws_iam_instance_profile.descarga.name
  user_data = replace(
    replace(replace(local.cloud_init, "__ROL__", "backend"), "__ORIGEN_CLIENTE__", "http://${aws_instance.cliente.public_ip}"),
    "__URL_APP__",
    local.app_url,
  )
  user_data_replace_on_change = true

  credit_specification {
    cpu_credits = "standard"
  }

  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    encrypted = true
  }

  depends_on = [aws_route_table_association.publica, aws_vpc_security_group_egress_rule.salida, aws_iam_role_policy.descarga]

  tags = { Name = "asistencia-backend" }
}

output "url_cliente" {
  value = "http://${aws_instance.cliente.public_ip}"
}

output "ip_cliente" {
  value = aws_instance.cliente.public_ip
}

output "ip_backend" {
  value = aws_instance.backend.public_ip
}
