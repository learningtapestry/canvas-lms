# Canvas LMS — GKE staging manifests

Kubernetes manifests for Canvas on GKE Autopilot. Managed data services (Cloud
SQL, Memorystore, GCS) come from `../environments/staging` Terraform, so this
layer is just the app: web, jobs, migrate, ingress.

## Workloads
| File | What |
|------|------|
| `app-namespace.yaml` | `canvas-staging` namespace |
| `app-service-account.yaml` | `canvas-app` KSA + Workload Identity annotation |
| `app-configmap.yaml` | non-secret env (`canvas-env`) |
| `app-config-files.yaml` | Canvas `config/*.yml` templates (`canvas-config-files`) |
| `app-secrets.yaml` | reference only — real Secret comes from External Secrets |
| `external-secrets-operator.yaml` | ClusterSecretStore + ExternalSecret (GCP SM) |
| `app-deployment.yaml` | `canvas-web` (Puma :3000) + Service |
| `jobs-deployment.yaml` | `canvas-jobs` (inst-jobs `script/delayed_job run`) |
| `db-migrate-job.yaml` | schema migrate Job |
| `app-hpa.yaml` | web autoscaling (2–6) |
| `app-ingress.yaml` | ingress-nginx, 10g uploads, TLS |
| `clusterissuer.yaml` / `certificate.yaml` | cert-manager + Cloud DNS |

## How config works
Canvas reads `config/*.yml` (not pure env vars). The `canvas-config-files`
ConfigMap holds ERB templates that read env vars; secret values arrive via the
`canvas-secrets` Secret (External Secrets → Secret Manager) and `canvas-env`.
Each file is mounted into `/usr/src/app/config/<file>` via `subPath`.

## Web serving
Runs **Puma directly on :3000** (non-root, Autopilot-friendly) instead of the
image's Passenger/nginx on :80. The Service maps 80→3000; ingress-nginx fronts
it with TLS. Health via Canvas' `/health_check`.

## Prerequisites
1. Terraform applied (`../environments/staging`) — cluster + data + secrets + SAs.
2. Cluster add-ons via Helm: `ingress-nginx`, `cert-manager`, `external-secrets`.
3. A **production Canvas image** pushed to Artifact Registry — assets
   precompiled (`RAILS_ENV=production COMPILE_ASSETS ... yarn build`). The repo
   `Dockerfile` is dev-only.

## Replace before applying
Project id (`propane-country-501515-c2`) and region (`us-central1`) are set.
Still to fill: real hostname (`canvas-staging.example.com`) and the cert-manager
account email.

## ⚠️ Open items to validate
- **GCS S3-interop**: Canvas' S3 client must honour the `endpoint` override in
  `amazon_s3.yml` to hit `storage.googleapis.com`. Verify on the real image; a
  small patch (or the native GCS/Fog path) may be needed.
- **First-time schema**: use `rake db:initial_setup` instead of `db:migrate` on
  the very first run.
- **Outbound email**: `outgoing_mail.yml` is a placeholder — wire a real relay.

## Apply order
```bash
kubectl apply -f app-namespace.yaml
kubectl apply -f app-service-account.yaml
kubectl apply -f app-configmap.yaml -f app-config-files.yaml
kubectl apply -f external-secrets-operator.yaml   # creates canvas-secrets
kubectl apply -f clusterissuer.yaml -f certificate.yaml
kubectl create -f db-migrate-job.yaml             # generateName → use create
kubectl apply -f app-deployment.yaml -f jobs-deployment.yaml -f app-hpa.yaml
kubectl apply -f app-ingress.yaml
```
