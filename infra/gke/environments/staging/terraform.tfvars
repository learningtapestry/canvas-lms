project_id = "REPLACE_ME" # target GCP project id
region     = "us-central1"
env        = "staging"

cluster_name = "canvas-gke"

# Lock down the control-plane public endpoint (office/VPN egress IPs).
# master_authorized_networks = [
#   { cidr_block = "203.0.113.0/24", display_name = "office" },
# ]

db_tier = "db-custom-2-7680" # 2 vCPU / 7.5 GB — bump for prod

attachments_bucket = "canvas-attachments-staging"

# Set false only in throwaway sandboxes.
deletion_protection = true
