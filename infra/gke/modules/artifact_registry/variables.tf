variable "repository_id" {
  type = string
}

variable "region" {
  type = string
}

variable "description" {
  type    = string
  default = "Canvas LMS container images"
}

variable "immutable_tags" {
  description = "Prevent tag overwrites"
  type        = bool
  default     = true
}

variable "keep_count" {
  description = "Number of most-recent image versions to retain"
  type        = number
  default     = 30
}
