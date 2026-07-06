variable "name" {
  description = "Globally-unique bucket name"
  type        = string
}

variable "location" {
  type    = string
  default = "US"
}

variable "storage_class" {
  type    = string
  default = "STANDARD"
}

variable "versioning" {
  type    = bool
  default = true
}

variable "expiration_days" {
  description = "Delete objects older than N days (0 = disabled)"
  type        = number
  default     = 0
}
