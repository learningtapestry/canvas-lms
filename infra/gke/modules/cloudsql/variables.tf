variable "name" {
  description = "Cloud SQL instance name"
  type        = string
}

variable "region" {
  type = string
}

variable "network_id" {
  description = "VPC network id for the private IP"
  type        = string
}

variable "database_version" {
  type    = string
  default = "POSTGRES_14"
}

variable "tier" {
  description = "Machine tier, e.g. db-custom-2-7680"
  type        = string
  default     = "db-custom-2-7680"
}

variable "availability_type" {
  type    = string
  default = "ZONAL"
}

variable "disk_size" {
  type    = number
  default = 50
}

variable "db_name" {
  type = string
}

variable "db_user" {
  type = string
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "deletion_protection" {
  type    = bool
  default = true
}
