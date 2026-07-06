terraform {
  # GCS backend provides state locking natively — no separate lock table needed.
  backend "gcs" {
    bucket = "REPLACE_ME-tf-state"
    prefix = "canvas-gke/staging"
  }
}
