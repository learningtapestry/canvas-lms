# Canvas LMS — GKE infrastructure

Terraform to run Canvas on GCP with managed services, so the Kubernetes layer
stays small. Lean by design: one `staging` environment first; prod is a later
copy with bigger tiers + HA.

## Layout
```
infra/gke/
├── environments/staging/   # root module (providers, backend, main, tfvars)
├── modules/                # network, gke_cluster, cloudsql, memorystore,
│                           # gcs_bucket, artifact_registry, service_account
└── k8s-manifests-staging/  # web + jobs + migrate + ingress (see its README)
```

## What it provisions
- **Network** — VPC, subnet (VPC-native ranges), Cloud NAT, Private Service Access
- **GKE Autopilot** — nodes/scaling managed; Workload Identity on by default
- **Cloud SQL** for PostgreSQL 14, private IP (Canvas primary DB)
- **Memorystore** for Redis — Canvas cache + inst-jobs locking
- **GCS** bucket for attachments, plus an **HMAC key** so Canvas' S3 driver uses
  GCS via the S3-interoperability API
- **Artifact Registry** — Canvas image (immutable tags)
- **Workload Identity** GSAs for app/jobs, external-secrets, cert-manager
- **Secret Manager** secret `canvas-secrets-staging`, assembled from the managed
  infra (DB, Redis URL, encryption key, GCS HMAC creds) and read by External
  Secrets Operator into Canvas' `config/*.yml`

## Authentication
Workload Identity (the GKE analogue of EKS IRSA) for keyless access to Cloud SQL,
GCS, and Secret Manager. The **one** exception is Canvas' S3 attachment driver,
which needs an access-key/secret pair — supplied by the GCS HMAC key, stored in
Secret Manager (not a long-lived Google key on disk).

## Bootstrap (once)
```bash
gcloud services enable container.googleapis.com sqladmin.googleapis.com \
  redis.googleapis.com servicenetworking.googleapis.com \
  artifactregistry.googleapis.com secretmanager.googleapis.com dns.googleapis.com

gsutil mb -l us-central1 gs://<project>-tf-state
gsutil versioning set on gs://<project>-tf-state   # then set it in backend.tf
```

## Apply
```bash
cd environments/staging
terraform init
terraform plan  -var project_id=<project>   # review — creates nothing
terraform apply -var project_id=<project>
```

## After apply
1. `terraform output` → fill placeholders in `k8s-manifests-staging/`.
2. Install add-ons via Helm: `ingress-nginx`, `cert-manager`, `external-secrets`.
3. Build + push a **production** Canvas image (assets precompiled) to Artifact
   Registry — the repo `Dockerfile` is the dev image and is not production-ready.
4. Apply the manifests.

## Prod later
Bump `db_tier`, set Cloud SQL `availability_type = REGIONAL`, Memorystore
`tier = STANDARD_HA`; copy `environments/staging` → `environments/prod`.
