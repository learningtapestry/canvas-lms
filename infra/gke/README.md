# Canvas LMS — GKE infrastructure

Terraform to run Canvas on GCP with managed services, so the Kubernetes layer
stays small. Lean by design: one `staging` environment first; prod is a later
copy with bigger tiers + HA.

## Layout

```
infra/gke/
├── environments/staging/   # root module (providers, backend, main, tfvars)
├── modules/                # network, gke_cluster, cloudsql, memorystore,
│                           # artifact_registry, service_account
└── k8s-manifests-staging/  # web + jobs + RCE API + migrate + ingress
```

## What it provisions

- **Network** — VPC, subnet (VPC-native ranges), Cloud NAT, Private Service Access
- **GKE Autopilot** — nodes/scaling managed; Workload Identity on by default
- **Cloud SQL** for PostgreSQL 18, private IP (Canvas primary DB)
- **Memorystore** for Redis — Canvas cache + inst-jobs locking
- **Local attachment storage** on a Kubernetes ReadWriteOnce Persistent Disk
- **Artifact Registry** — Canvas image (immutable tags)
- **Workload Identity** GSAs for app/jobs, external-secrets, cert-manager
- **Secret Manager** secret `canvas-secrets-staging`, assembled from the managed
  infra and generated Canvas/RCE credentials. External Secrets materializes the
  application env and Canvas's RCE `vault_contents.yml`.
- **Canvas RCE API** as a separate Kubernetes workload with its own HTTPS host

## Authentication

Workload Identity (the GKE analogue of EKS IRSA) for keyless access to Cloud SQL,
Artifact Registry, and Secret Manager. No static Google service-account keys are
stored on disk.

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

1. Install add-ons via Helm: `ingress-nginx`, `cert-manager`, `external-secrets`.
2. Build + push a **production** Canvas image (assets precompiled) to Artifact
   Registry — the repo `Dockerfile` is the dev image and is not production-ready.
3. Point both `class.nbdmath.org` and `rce.class.nbdmath.org` at the ingress
   load balancer. DNS must resolve before cert-manager's HTTP-01 validation.
4. Apply the manifests in the order documented in
   `k8s-manifests-staging/README.md`; that includes RCE secrets/config, the RCE
   API workload, the Canvas migration, and the web/jobs rollout.

## Prod later

Bump `db_tier`, set Cloud SQL `availability_type = REGIONAL`, Memorystore
`tier = STANDARD_HA`; copy `environments/staging` → `environments/prod`.
