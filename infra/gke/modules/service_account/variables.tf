variable "project_id" {
  type = string
}

variable "account_id" {
  description = "GSA account id (left of @)"
  type        = string
}

variable "display_name" {
  type    = string
  default = ""
}

variable "project_roles" {
  description = "Project-level roles to grant this GSA"
  type        = list(string)
  default     = []
}

variable "ksa_namespace" {
  description = "Kubernetes namespace of the bound KSA"
  type        = string
}

variable "ksa_name" {
  description = "Kubernetes ServiceAccount name to bind"
  type        = string
}
