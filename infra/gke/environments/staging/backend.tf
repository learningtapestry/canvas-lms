terraform {
  # GCS backend provides state locking natively — no separate lock table needed.
  backend "gcs" {
    bucket = "propane-country-501515-c2-tf-state"
    prefix = "canvas-gke/staging"
  }
}
