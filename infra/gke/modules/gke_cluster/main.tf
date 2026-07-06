terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

# GKE Autopilot cluster. Autopilot manages nodes, scaling, and enables
# Workload Identity by default — no node pools / cluster-autoscaler to define.
resource "google_container_cluster" "this" {
  name     = var.name
  location = var.region

  enable_autopilot    = true
  networking_mode     = "VPC_NATIVE"
  network             = var.network_id
  subnetwork          = var.subnet_id
  deletion_protection = var.deletion_protection

  release_channel {
    channel = var.release_channel
  }

  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_range_name
    services_secondary_range_name = var.services_range_name
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block
  }

  # Restrict who can reach the public control-plane endpoint.
  dynamic "master_authorized_networks_config" {
    for_each = length(var.master_authorized_networks) > 0 ? [1] : []
    content {
      dynamic "cidr_blocks" {
        for_each = var.master_authorized_networks
        content {
          cidr_block   = cidr_blocks.value.cidr_block
          display_name = cidr_blocks.value.display_name
        }
      }
    }
  }
}
