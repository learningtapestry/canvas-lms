# Canvas LMS — GKE staging manifests

Runs Canvas (from the **`cloud66-prod`** branch) on GKE Autopilot. Managed data
services come from `../environments/staging` Terraform; this layer is the app.

## Config model (matches Cloud66)
Canvas reads `config/*.yml`. The production image (built from `cloud66-prod`)
ships `config/*.yml.cloud66` templates that read env vars. Each pod's start
command copies `*.yml.cloud66 -> *.yml` (the Cloud66 `after_checkout` hook
equivalent), then boots. `amazon_s3` and `outgoing_mail` are intentionally not
copied → **local file storage, no SMTP**.

- **Secret env** (`canvas-secrets`, via External Secrets ← Secret Manager):
  `POSTGRESQL_ADDRESS/PASSWORD`, `REDIS_ADDRESS`, `ENCRYPTION_KEY`,
  `JWT_ENCRYPTION_KEY`.
- **Non-secret env** (`canvas-env` ConfigMap): DB name/user/port, `REDIS_PORT`,
  `CANVAS_REDIS_DB`, `CANVAS_DOMAIN`, `CANVAS_LMS_ADMIN_EMAIL`,
  `FILE_STORAGE_PATH_PREFIX`, etc.
- **Rich Content Editor config:** `rce-api.yaml` supplies
  `config/dynamic_settings.yml`, while External Secrets renders the matching
  `config/vault_contents.yml` from the generated RCE signing and encryption
  keys. Both files are mounted into the web, jobs, and migration pods.

## Runtime requirements (learned the hard way)
- **HTTPS is mandatory.** Canvas hardcodes `config.force_ssl = true`, so the
  session cookie is `secure` — it won't work over plain HTTP, and login fails
  with a CSRF 400. The ingress must terminate TLS.
- **Passenger, not `rails server`.** Canvas sets `public_file_server.enabled =
  false` and relies on Passenger/nginx to serve `public/dist`. The web pod runs
  `passenger start` (the image is `instructure/ruby-passenger`).
- **`SECRET_KEY_BASE` must be provided** (via the secret) — Cloud66 auto-injects
  it; on GKE Canvas can't sign the session cookie without it.
- **The image tools require Canvas RCE API.** The separate
  `canvas-rce-api` Deployment receives the same signing/encryption key pair that
  Canvas reads from `vault_contents.yml`. Canvas reaches it at
  `https://rce.class.nbdmath.org` through the configured `app-host`.
- **`RAILS_SERVE_STATIC_FILES` has no effect** — Canvas ignores it.

## Storage (approach B)

Local file storage on a single **ReadWriteOnce** Persistent Disk (`canvas-files`
PVC) mounted at `/usr/src/app/storage/files`. The **web** and **jobs** pods are
**single-replica** and colocated on one node (pod affinity) so they can share
the disk. No object storage / buckets. Web uses `Recreate` deploys (RWO can't
multi-attach). Prod should move to Filestore (RWX) or object storage.

## Workloads

| File | What |
|------|------|
| `app-namespace.yaml` | `canvas-staging` namespace |
| `app-service-account.yaml` | `canvas-app` KSA (Workload Identity) |
| `app-configmap.yaml` | non-secret env (`canvas-env`) |
| `app-secrets.yaml` | reference only — real Secret via External Secrets |
| `external-secrets-operator.yaml` | ClusterSecretStore + Canvas/RCE ExternalSecrets |
| `pvc.yaml` | `canvas-files` RWO PD for local storage |
| `rce-api.yaml` | RCE dynamic config, API Deployment, Service, and TLS ingress |
| `app-deployment.yaml` | `canvas-web` (Passenger :3000) + Service |
| `jobs-deployment.yaml` | `canvas-jobs` (`script/delayed_job run`) |
| `db-migrate-job.yaml` | migrate Job (first run: also `db:initial_setup`) |
| `app-ingress.yaml` | ingress-nginx, 10g uploads, TLS |
| `clusterissuer.yaml` | cert-manager Let's Encrypt issuer (HTTP-01) |

## Prerequisites

1. Terraform applied (`../environments/staging`) — cluster, Cloud SQL (PG18),
   Memorystore (no AUTH), SAs, secret.
2. Helm add-ons installed: ingress-nginx, cert-manager, external-secrets
   (SAs Workload-Identity annotated).
3. A **production Canvas image** built from `cloud66-prod` in Artifact Registry
   (see `.github/workflows/build-canvas-image.yml`).
4. DNS A records for both `class.nbdmath.org` and `rce.class.nbdmath.org`
   pointing to the ingress load balancer (`35.222.47.79`). The RCE record must
   resolve before its ingress is applied so Let's Encrypt HTTP-01 can validate it.

## Check before applying

Confirm the admin email, cert-manager account email, and both DNS records. The
checked-in Canvas and RCE hostnames are `class.nbdmath.org` and
`rce.class.nbdmath.org`.

## Apply order

```bash
kubectl apply -f app-namespace.yaml
kubectl apply -f app-service-account.yaml
kubectl apply -f app-configmap.yaml
kubectl apply -f clusterissuer.yaml
kubectl apply -f external-secrets-operator.yaml   # creates both Canvas secrets
kubectl apply -f pvc.yaml
kubectl apply -f rce-api.yaml
kubectl create -f db-migrate-job.yaml             # generateName → use create
kubectl apply -f app-deployment.yaml -f jobs-deployment.yaml
kubectl apply -f app-ingress.yaml
```

Wait for the secret reconciliation and both deployments before testing the
editor. Mounts that use `subPath` require a pod rollout after future RCE config
or credential changes.

```bash
kubectl wait --for=condition=Ready externalsecret/canvas-secret \
  externalsecret/canvas-rce-credentials -n canvas-staging --timeout=120s
kubectl rollout status deployment/canvas-rce-api -n canvas-staging
kubectl rollout status deployment/canvas-web -n canvas-staging
curl -fsS https://rce.class.nbdmath.org/
```
