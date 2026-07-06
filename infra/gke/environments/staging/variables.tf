variable "project_id" {
  description = "GCP project id"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "env" {
  description = "Environment name (namespace suffix)"
  type        = string
  default     = "staging"
}

# --- GKE ---
variable "cluster_name" {
  type    = string
  default = "canvas-gke"
}

variable "master_authorized_networks" {
  description = "CIDRs allowed to reach the cluster control plane"
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = []
}

# --- Cloud SQL ---
variable "db_tier" {
  description = "Cloud SQL machine tier (Canvas is DB-heavy)"
  type        = string
  default     = "db-custom-2-7680"
}

variable "db_name" {
  type    = string
  default = "canvas_production"
}

variable "db_user" {
  type    = string
  default = "canvas"
}

# --- GCS ---
variable "attachments_bucket" {
  description = "Globally-unique bucket for Canvas file attachments"
  type        = string
  default     = "canvas-attachments-staging"
}

variable "deletion_protection" {
  type    = bool
  default = true
}
