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

variable "zone" {
  description = "Preferred zone for a ZONAL instance (null = let Google choose)"
  type        = string
  default     = null
}

variable "disk_size" {
  type    = number
  default = 50
}

# ENCRYPTED_ONLY rejects unencrypted connections (defense-in-depth on top of
# the private IP). Canvas sets no explicit sslmode, so libpq defaults to
# 'prefer' and still negotiates SSL — connections keep working, now encrypted.
variable "ssl_mode" {
  type    = string
  default = "ENCRYPTED_ONLY"
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
