# Canvas LMS — GCP/GKE Infrastructure Summary

Building blocks and context for the Canvas LMS cloud infrastructure. This is the
high-level map; see `infra/gke/README.md` and the per-directory READMEs for
operational detail.

## Project context

- **Goal:** migrate Canvas LMS off its current Cloud66/AWS (EC2 + Redis +
  Postgres) hosting onto **Google Cloud / GKE**, starting lean with a single
  `staging` environment and managed data services. Prod follows later as a copy
  with larger tiers + HA.
- **Origin of the object-storage need:** Canvas' attachment layer uses an S3
  driver; on GCP this is served by **GCS via the S3-interoperability API**
  (HMAC key), which is what replaces the "S3-compatible service" requirement.
- **Reference:** patterns (module + manifest layout, External Secrets,
  cert-manager, Workload Identity) were modelled on an existing EKS setup, then
  simplified for GKE. No content from that reference lives here.

## The application (what we're deploying)

- **Canvas LMS** — large Rails 8 / Ruby 3.4 monolith.
- **Web:** served by **Puma on :3000** (non-root, Autopilot-friendly) instead of
  the base image's Passenger/nginx on :80.
- **Workers:** **inst-jobs** (Instructure's `delayed_job`) + `switchman-inst-jobs`
  (sharding), run via `script/delayed_job run`. **Not Sidekiq.**
- **Data deps:** PostgreSQL (switchman sharding), Redis (cache + job locking),
  object storage for attachments. **No Elasticsearch** (not required by core).
- **Config:** file-driven (`config/*.yml`), injected as mounted YAML rendered
  via ERB from env vars — not pure env config.
- **Image:** the repo `Dockerfile` is **dev-only**; production needs a separate
  build with precompiled assets (`yarn build`, `RAILS_ENV=production`).

## GCP project

| | |
|---|---|
| **Project ID** | `propane-country-501515-c2` (display name "NBD Math for the DTRI" — shared project, empty of prior infra) |
| **Region** | `us-central1` |
| **Billing** | Enabled — `billingAccounts/0197F0-B92603-CB825F` |
| **Org** | No organization; policy `iam.allowedPolicyMemberDomains` is set (restricts cross-domain IAM grants) |
| **Default network** | An auto-mode `default` network exists; we provision a separate custom VPC |
| **APIs enabled** | compute, container, sqladmin, redis, servicenetworking, artifactregistry, secretmanager, dns |

## Architecture building blocks

| Layer | GCP building block | Notes |
|-------|--------------------|-------|
| Network | Custom VPC + subnet (VPC-native ranges), Cloud NAT, Private Service Access | Private nodes/data; egress via NAT |
| Compute | **GKE Autopilot** | Managed nodes/scaling; Workload Identity on by default |
| Web | `canvas-web` Deployment (Puma :3000) + HPA (2–6) | Service maps 80→3000 |
| Workers | `canvas-jobs` Deployment (`script/delayed_job run`, 2 replicas) | inst-jobs |
| Migrate | `canvas-db-migrate` Job | `db:initial_setup` first run, then `db:migrate` |
| Database | **Cloud SQL** for PostgreSQL 14, private IP | `db-custom-2-7680` staging |
| Cache/jobs | **Memorystore** for Redis, auth + TLS | replaces self-hosted Redis |
| Attachments | **GCS** bucket + **HMAC key** (S3-interop) | Canvas S3 driver → `storage.googleapis.com` |
| Registry | **Artifact Registry** (Docker, immutable tags) | Canvas image |
| Secrets | **Secret Manager** + External Secrets Operator | assembled by Terraform, synced into `canvas-secrets` |
| Identity | **Workload Identity** + 3 GSAs (app, external-secrets, cert-manager) | keyless; HMAC is the one exception |
| Ingress/TLS | **ingress-nginx** + cert-manager (Cloud DNS DNS01) | 10g upload limit for Canvas |

## Authentication model

- **Workload Identity** is the primary mechanism (GKE analogue of EKS IRSA):
  each Kubernetes ServiceAccount impersonates a least-privilege Google service
  account — no static keys. On Autopilot it's enabled by default.
  - `canvas-app` → Cloud SQL client, GCS object admin (bucket-scoped),
    Secret Manager accessor (secret-scoped).
  - `canvas-external-secrets` → Secret Manager accessor.
  - `canvas-cert-manager` → Cloud DNS admin.
- **One exception:** Canvas' S3 attachment driver needs an access-key/secret, so
  attachments use a **GCS HMAC key** (stored in Secret Manager), not keyless WI.

## Repository layout (all in this repo — nothing committed elsewhere)

```
infra/
├── INFRASTRUCTURE-SUMMARY.md   # this file
└── gke/
    ├── README.md
    ├── environments/staging/   # Terraform root (providers, backend, main, tfvars)
    ├── modules/                # network, gke_cluster, cloudsql, memorystore,
    │                           # gcs_bucket, artifact_registry, service_account
    └── k8s-manifests-staging/  # web, jobs, migrate, ingress, ESO, cert-manager
```

Terraform modules are app-agnostic and version-pinned (`google ~> 6.0`,
Terraform `>= 1.5`). State: GCS backend (bucket TBD).

## Key decisions

1. **Lean first** — one staging env, managed data services, defer prod/HA and
   Elasticsearch.
2. **GKE Autopilot** — removes node-pool/autoscaler/CSI ops (team has k8s
   experience but no need to run nodes).
3. **Managed data** — Cloud SQL + Memorystore instead of self-hosted pods.
4. **GCS S3-interop** for attachments — smallest change to Canvas' storage layer.
5. **Config as mounted YAML** — matches how Canvas actually reads config.
6. **Puma on a high port** — avoids privileged-port/root issues under Autopilot.

## Current status

- **Done:** Terraform + manifests scaffolded and validated; project wired in;
  GCP APIs enabled; project inspected (empty, billing on).
- **Branch:** `infrastructure` (in this repo). Commits are local — push pending
  `arielr-lt` write access to `learningtapestry/canvas-lms`.
- **Not yet applied:** no GCP resources created beyond enabling APIs.

## Open items / to fill

- Terraform **state bucket** (`backend.tf` placeholder) — create during bootstrap.
- Real **hostname** (replacing `canvas-staging.example.com`) + cert-manager email.
- **GCS S3-interop `endpoint`** must be honoured by Canvas' S3 client — validate
  on the real image (may need a small patch or the native Fog-GCS path).
- **Production Canvas image** with precompiled assets (CI build).
- **Outbound email** relay (placeholder in `outgoing_mail.yml`).

## Bootstrap → apply flow

1. Enable APIs (done). 2. Create GCS state bucket, set in `backend.tf`.
3. `terraform plan` (review) → `apply`. 4. Install Helm add-ons (ingress-nginx,
cert-manager, external-secrets). 5. Build/push prod image. 6. Apply manifests.
