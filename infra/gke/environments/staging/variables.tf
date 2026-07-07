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

variable "db_zone" {
  description = "Zone for the ZONAL Cloud SQL instance (co-located with pods/PD)"
  type        = string
  default     = "us-central1-f"
}

variable "db_name" {
  type    = string
  default = "canvas_production"
}

variable "db_user" {
  type    = string
  default = "canvas"
}

variable "deletion_protection" {
  type    = bool
  default = true
}

variable "github_repository" {
  description = "owner/repo allowed to push images via Workload Identity Federation"
  type        = string
  default     = "learningtapestry/canvas-lms"
}

# --- Canvas crypto keys ---
# For a FRESH install leave these null -> Terraform generates random keys.
# When importing EXISTING data (e.g. a prod migration), the stored data is
# encrypted with the source instance's keys, so Canvas must reuse them or it
# can't decrypt. Supply them out-of-band and NEVER commit the values:
#   export TF_VAR_encryption_key='...'
#   export TF_VAR_jwt_encryption_key='...'
#   export TF_VAR_secret_key_base='...'
variable "encryption_key" {
  description = "Canvas ENCRYPTION_KEY (>=20 chars). null = generate. Set via TF_VAR for migrated data; do NOT commit."
  type        = string
  default     = null
  sensitive   = true
}

variable "jwt_encryption_key" {
  description = "Canvas JWT_ENCRYPTION_KEY. null = generate. Set via TF_VAR for migrated data; do NOT commit."
  type        = string
  default     = null
  sensitive   = true
}

variable "secret_key_base" {
  description = "Rails SECRET_KEY_BASE (session cookie signing). null = generate. Set via TF_VAR to keep sessions stable across applies; do NOT commit."
  type        = string
  default     = null
  sensitive   = true
}
