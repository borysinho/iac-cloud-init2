terraform {
  required_version = ">= 1.11, < 2.0"

  backend "s3" {
    key          = "cloud-init-2/opentofu/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region              = var.region
  allowed_account_ids = [var.aws_account]
}

variable "region" {
  type        = string
  description = "Región de AWS donde existe el par de claves globomatics."
  default     = "us-east-2"
}

variable "ssh_cidr" {
  type        = string
  description = "IPv4 pública del operador en formato CIDR /32."

  validation {
    condition     = can(cidrnetmask(var.ssh_cidr)) && endswith(var.ssh_cidr, "/32")
    error_message = "Ingresa una sola IPv4 pública con el sufijo /32."
  }
}

variable "state_bucket" {
  type        = string
  description = "Bucket privado preparado para el estado y el paquete de la aplicación."
}

variable "aws_account" {
  type        = string
  description = "Cuenta AWS en la que se preparó el bucket."
}
