# Helm add-on values (staging)

Values files that pin the Helm-installed cluster add-ons to their intended
config — most importantly **small burstable resource requests**, so GKE
Autopilot doesn't bill each pod its default 0.5 vCPU / 2Gi. Keeping these in the
repo prevents a clean reinstall from silently regressing to ~$210/mo of add-on
compute (see the cost note at the bottom).

These add-ons are installed **imperatively via Helm** (not by Terraform). The
Terraform in `../environments/staging` creates the Google service accounts and
Workload Identity bindings the values reference; Helm consumes them.

## Prerequisites

```bash
gcloud container clusters get-credentials canvas-gke --region us-central1 --project propane-country-501515-c2
helm repo add jetstack https://charts.jetstack.io
helm repo add external-secrets https://charts.external-secrets.io
helm repo update
```

## Install / upgrade

```bash
# cert-manager (chart v1.20.3)
helm upgrade --install cert-manager jetstack/cert-manager \
  -n cert-manager --create-namespace --version v1.20.3 \
  -f cert-manager.values.yaml

# external-secrets (chart 2.7.0)
helm upgrade --install external-secrets external-secrets/external-secrets \
  -n external-secrets --create-namespace --version 2.7.0 \
  -f external-secrets.values.yaml
```

`upgrade --install` is idempotent — safe to re-run. Prefer `-f <file>` over
`--reuse-values` so the repo file is the source of truth.

> ingress-nginx is also Helm-installed but not yet pinned here. Add its values
> the same way if/when you tune it.

## Why the resources look tiny

cert-manager and external-secrets are near-idle controllers (a few tens of MiB,
almost no CPU). We set **burstable** requests — `requests` (50m/128Mi) below
`limits` (500m/512Mi):

- Autopilot bills the **request**, so each pod costs ~$2/mo instead of ~$10.
- Pods **burst** up to the limit during real work (cert issuance, secret
  reconciliation), so they aren't starved.

Effect: cert-manager and external-secrets dropped from **~$70/mo each to ~$6/mo
each**. If cert-manager feels slow while issuing a real certificate later, raise
its `requests.cpu`.
