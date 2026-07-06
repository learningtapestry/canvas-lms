# Canvas LMS — GCP/GKE Infrastructure Summary

Building blocks and context for the Canvas LMS cloud infrastructure. This is the
high-level map; see `infra/gke/README.md` and the per-directory READMEs for
operational detail.

## Project context

- **Goal:** migrate Canvas LMS off its current Cloud66/AWS (EC2 + Redis +
  Postgres) hosting onto **Google Cloud / GKE**, starting lean with a single
  `staging` environment and managed data services. Prod follows later as a copy
  with larger tiers + HA.
- **File storage:** the running app uses **local file storage** (confirmed with
  the dev) — no object storage. On k8s this is a ReadWriteOnce Persistent Disk
  shared by the single-replica web+jobs pods. (The earlier "S3-compatible
  service" idea is set aside; object storage would be a future option.)
- **Reference:** patterns (module + manifest layout, External Secrets,
  cert-manager, Workload Identity) were modelled on an existing EKS setup, then
  simplified for GKE. No content from that reference lives here.

## The application (what we're deploying)

- **Canvas LMS** — large Rails 8 / Ruby 3.4 monolith. **We track the
  `cloud66-prod` branch** — the exact code Cloud66 runs in production (has
  `config/*.yml.cloud66` templates + `.cloud66/` deploy metadata).
- **Web:** served by **Puma on :3000** (non-root, Autopilot-friendly).
- **Workers:** **inst-jobs** (`delayed_job`) + `switchman-inst-jobs`, run via
  `script/delayed_job run`. **Not Sidekiq.**
- **Data deps:** PostgreSQL, Redis (cache + job locking), **local file storage**
  for attachments (no buckets — confirmed with the dev). **No Elasticsearch.**
- **Config (matches Cloud66):** env-var driven. The image ships
  `config/*.yml.cloud66` templates; each pod's start command copies
  `*.yml.cloud66 → *.yml` (the Cloud66 `after_checkout` hook), then boots.
  `amazon_s3`/`outgoing_mail` are not copied → local storage, no SMTP.
- **Real env var names** (from cloud66-prod): `POSTGRESQL_ADDRESS/PORT/DATABASE/
  USERNAME/PASSWORD`, `REDIS_ADDRESS/PORT`, `CANVAS_REDIS_DB`, `ENCRYPTION_KEY`,
  `JWT_ENCRYPTION_KEY`, `CANVAS_DOMAIN`, `CANVAS_LMS_ADMIN_EMAIL`,
  `FILE_STORAGE_PATH_PREFIX`.
- **Stack (cloud66 manifest):** Ruby 3.4.9, Node 20, Postgres 18.3, Redis 8.6.2.
- **Image:** built from `cloud66-prod` using the repo's maintained
  **`Dockerfile.production`** (runs `bundle install` + `canvas:compile_assets`).
  The repo `Dockerfile` is dev-only.

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
| Database | **Cloud SQL** for PostgreSQL **17**, private IP | `db-custom-2-7680` staging (prod runs 18.3) |
| Cache/jobs | **Memorystore** for Redis, **AUTH disabled** | matches cloud66 `redis.yml` (plain redis://) |
| Attachments | **Local storage** on a **ReadWriteOnce PD** (`canvas-files` PVC) | web+jobs single-replica, colocated (approach B); prod → Filestore/object storage |
| Registry | **Artifact Registry** (Docker, immutable tags) | Canvas image (built from cloud66-prod) |
| Secrets | **Secret Manager** + External Secrets Operator | `POSTGRESQL_*`, `REDIS_ADDRESS`, `ENCRYPTION_KEY`, `JWT_ENCRYPTION_KEY` |
| Identity | **Workload Identity** + 3 GSAs (app, external-secrets, cert-manager) | keyless; HMAC is the one exception |
| Ingress/TLS | **ingress-nginx** + cert-manager (Cloud DNS DNS01) | 10g upload limit for Canvas |

## Authentication model

- **Workload Identity** is the primary mechanism (GKE analogue of EKS IRSA):
  each Kubernetes ServiceAccount impersonates a least-privilege Google service
  account — no static keys. On Autopilot it's enabled by default.
  - `canvas-app` → Cloud SQL client, Secret Manager accessor (secret-scoped).
  - `canvas-external-secrets` → Secret Manager accessor.
  - `canvas-cert-manager` → Cloud DNS admin.
  - `github-actions` → Artifact Registry writer (via Workload Identity
    Federation, for the image-build workflow).
- No static keys anywhere (local file storage removed the need for an HMAC key).

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
4. **Local file storage** on a RWO PD (approach B) — matches current prod; cheap
   for staging. Prod needs Filestore (RWX) or object storage.
5. **Reuse the cloud66 config templates** — copy `*.yml.cloud66 → *.yml` at
   start; matches exactly how the running app is configured.
6. **Puma on a high port** — avoids privileged-port/root issues under Autopilot.

## Current status

- **Done:** Terraform + manifests scaffolded and validated; project wired in;
  GCP APIs enabled; project inspected (empty, billing on).
- **Branch:** `infrastructure` (in this repo). Commits are local — push pending
  `arielr-lt` write access to `learningtapestry/canvas-lms`.
- **Not yet applied:** no GCP resources created beyond enabling APIs.

## Open items / to fill

- Real **hostname** (replacing `canvas-staging.example.com`) + cert-manager email.
- **Production Canvas image** built from `cloud66-prod` (GitHub Actions workflow).
- First deploy: run `db:initial_setup` (needs `CANVAS_LMS_ADMIN_EMAIL`, maybe
  admin password) before the app can serve.
- Prod file storage: move off the single RWO PD to Filestore (RWX) or object
  storage for HA/scale.
- **Outbound email** relay (placeholder in `outgoing_mail.yml`).

## Bootstrap → apply flow

1. Enable APIs (done). 2. Create GCS state bucket, set in `backend.tf`.
3. `terraform plan` (review) → `apply`. 4. Install Helm add-ons (ingress-nginx,
cert-manager, external-secrets). 5. Build/push prod image. 6. Apply manifests.
