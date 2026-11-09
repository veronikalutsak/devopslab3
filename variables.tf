variable "region" {
  type    = string
  default = "eu-central-1"
}

variable "project" {
  type    = string
  default = "mini-api"
}

# Для локального емулятора (Floci), напр. "http://localhost:4566".
# Для реального AWS залишити null.
variable "local_endpoint" {
  type    = string
  default = null
}

variable "lambda_s3_endpoint" {
  type    = string
  default = null
}