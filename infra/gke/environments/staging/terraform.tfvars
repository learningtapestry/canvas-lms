project_id = "propane-country-501515-c2" # target GCP project id
region     = "us-central1"
env        = "staging"

cluster_name = "canvas-gke"

# Lock down the control-plane public endpoint to admin egress IPs.
# NOTE: /32 below is a single operator IP — REPLACE with your stable
# VPN/office CIDR(s). If your IP changes you'll lose kubectl until you
# update this and re-apply (recoverable via the Cloud Console).
master_authorized_networks = [
  { cidr_block = "148.227.69.243/32", display_name = "operator" },
]

db_tier = "db-custom-2-7680" # 2 vCPU / 7.5 GB — bump for prod

# Set false only in throwaway sandboxes.
deletion_protection = true
