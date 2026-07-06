variable "name" {
  type = string
}

variable "region" {
  type = string
}

variable "network_id" {
  type = string
}

variable "tier" {
  description = "BASIC (no HA) or STANDARD_HA"
  type        = string
  default     = "BASIC"
}

variable "memory_size_gb" {
  type    = number
  default = 1
}

variable "redis_version" {
  type    = string
  default = "REDIS_7_2"
}

variable "auth_enabled" {
  description = "Enable Redis AUTH + TLS (Canvas cloud66 config expects it off)"
  type        = bool
  default     = false
}
