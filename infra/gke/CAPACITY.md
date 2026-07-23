# Canvas on GKE — Capacity & Scaling

Internal snapshot for the traffic/load discussion (Ariel / Danilo / Alex).
Point-in-time; update as the environment changes.

Site is live at **https://class.nbdmath.org**, but it runs on a deliberately
**cost-optimized pilot tier** — fine for a small pilot, not yet sized for
production load.

## Current

- **Web:** 1 pod (Passenger, ~3 concurrent dynamic requests)
- **Jobs:** 1 worker (background queue in Postgres)
- **DB:** Cloud SQL Postgres, 1 vCPU / 3.75 GB, single zone
- **Cache:** Memorystore Redis, 1 GB (no HA)
- **Files:** local storage on a single-node (ReadWriteOnce) disk
- No HA, no web autoscaling, not load-tested

## Hard limit

Local file storage on a **ReadWriteOnce** disk pins web + jobs to one node, so we
**can't add web replicas until files move to GCS object storage (recommended) or
Filestore (RWX)**. That's the real blocker to horizontal scaling.

## To decide

- Expected launch scale (schools/families, peak concurrent users)?
- Production target date vs staying a pilot?
- Storage direction: **GCS** vs Filestore?
- HA at launch, or harden later?
- Budget for scaling up (trades against the ~$200/mo just optimized away)?

## References

- Infra-as-code + architecture: `infra/README.md`, PR #4
- Can run a k6/Artillery load test for real numbers instead of estimates.
