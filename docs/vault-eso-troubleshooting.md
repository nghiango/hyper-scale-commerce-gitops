# Vault + External Secrets Operator — Migration Notes & Troubleshooting

Evidence log from moving hardcoded credentials out of git into Vault
(dev mode, in-cluster) synced by External Secrets Operator (ESO) on the
`kind-hyperscale-k8s` cluster. Documents every problem hit, its root cause,
and the fix that landed.

## Initial state (the problem being solved)

- `postgresHa.credentials.password`, `replicatorPassword` and
  `redis.auth.password` were committed plaintext in
  `charts/application/values.yaml` and `charts/infrastructure/values.yaml`.
- Postgres passwords were injected as literal env vars (`value:`), visible via
  `kubectl get pod -o yaml`, not just in git.
- The Grafana admin Secret `local-platform-credentials` was referenced by
  `secretKeyRef` but created nowhere in the repo — unmanaged manual state.

## Architecture that landed

- `charts/infrastructure/templates/vault.yaml` — dev-mode Vault Deployment +
  Service + SA bound to `system:auth-delegator` (needed for TokenReview).
- `charts/infrastructure/templates/vault-bootstrap.yaml` — Job (ArgoCD **Sync**
  hook) that enables `kubernetes` auth, writes the `eso` policy/role, and seeds
  `secret/hyperscale/{postgres,redis,platform}` with `urandom`-generated
  passwords if absent (idempotent).
- `charts/infrastructure/templates/external-secrets.yaml` — `vault-auth` SA +
  long-lived token Secret, `vault-backend` ClusterSecretStore, ExternalSecrets
  for `postgres-credentials` and `redis-secret`.
- `charts/platform/templates/external-secrets.yaml` — ExternalSecret for
  `local-platform-credentials`.
- `argocd/applications.yaml` — added `external-secrets` Application (upstream
  Helm chart, pinned `0.10.5`).
- All workloads switched from literal `value:` env to `secretKeyRef`; plaintext
  credentials removed from both `values.yaml` files and `redis.yaml`'s
  committed Secret deleted.

## Problems encountered and fixes

### 1. PostSync hook deadlock

**Symptom:** `vault-bootstrap` Job never created; sync stuck at
`Running — waiting for healthy state of apps/StatefulSet/postgres-ha`.

**Root cause:** PostSync hooks only run *after* all synced resources report
healthy. `postgres-ha` can never become healthy without the secrets this job
seeds → circular wait.

**Fix:** Changed hook annotation to `argocd.argoproj.io/hook: Sync` so the job
runs during the sync operation, not after health assessment.

### 2. Bootstrap pod polluting the `vault` Service endpoints

**Symptom:** Job stuck on "Waiting for Vault..."; `kubectl get endpoints vault`
showed two endpoints — the Vault pod *and the Job pod itself*.

**Root cause:** The Job's pod template carried
`app.kubernetes.io/component: vault`, matching the Service selector. Ready pods
join endpoints even with nothing listening on 8200, so ~50% of connections
went to a black hole.

**Fix:** Gave the Job pod a distinct label
`app.kubernetes.io/component: vault-bootstrap`.

### 3. `default-deny-all` NetworkPolicy blocked everything new

**Symptom:** Job couldn't reach Vault; later, Vault couldn't perform
TokenReview.

**Root cause:** The namespace has `default-deny-all` for both ingress and
egress. No policy allowed traffic to the new `vault` pods, and Vault's outbound
call to the Kubernetes API was also denied.

**Fix:** Added `allow-vault-ingress` (port 8200 from `hyperscale-commerce` pods
and the `external-secrets` namespace) and `allow-vault-kube-api-egress`.

### 4. Apiserver egress port is post-DNAT (6443, not 443)

**Symptom:** ESO `ClusterSecretStore` stuck at "unable to create client";
manual `auth/kubernetes/login` returned `403 permission denied`; `wget` to the
`kubernetes` Service ClusterIP:443 hung from the Vault pod.

**Root cause:** NetworkPolicy evaluates the *post-DNAT* destination. The
`kubernetes` Service exposes 443, but its endpoints are the real apiserver on
**6443** — the egress rule allowing only 443 didn't match.

**Fix:** `allow-vault-kube-api-egress` now permits TCP 443 **and** 6443.

### 5. Rotating the secret doesn't rotate the database

**Symptom:** After secrets synced, replicas logged
`password authentication failed for user "postgres"` and the app failed the
same way for user `hyperscale`.

**Root cause:** Passwords live in `pgdata` from `initdb` time. Changing the env
var/secret doesn't update stored credentials.

**Fix:** `ALTER USER postgres|replicator|hyperscale WITH PASSWORD '<vault value>'`
on the primary. (Gotcha found live: the app authenticates as the `hyperscale`
role, not `postgres`.)

### 6. Pre-existing replica corruption unmasked

**Symptom:** `postgres-ha-1`/`postgres-ha-2` crashlooping with
`pg_hba.conf contains no entries` and Patroni start/stop churn (43h of
restarts before this change).

**Fix:** Deleted the `postgres-data` PVCs for both replicas and force-deleted
the pods; Patroni re-cloned from the healthy primary. All three members
healthy afterward.

### 7. Secret/consumer skew on rotation

**Symptom:** `redis-0` still held the old committed password while
`redis-secret` already contained the Vault-generated one — new pods would have
failed auth.

**Fix:** Restarted `redis-0` to pick up the new Secret. General rule: after any
credential change, restart both the server *and* its clients.

## Operational notes

- Dev-mode Vault is in-memory: on restart all secrets vanish. The next ArgoCD
  sync re-runs the bootstrap job (Sync hook) and re-seeds **new random**
  passwords — DB roles and dependent pods then need re-rotation/restart.
- `vault.devRootToken: "root"` is committed intentionally — dev mode is
  local-only. Real environments need a persistent Vault with auto-unseal and no
  committed token.
- Sync order: `external-secrets` must exist before the infra app or
  ExternalSecret/ClusterSecretStore applies fail on missing CRDs (self-heals
  via auto-sync retry).

## Final verified state

- All 4 Applications (`external-secrets`, `hyperscale-local`,
  `-infrastructure`, `-platform`): **Synced / Healthy**.
- All 3 ExternalSecrets: **SecretSynced**.
- `/actuator/health` on the app: `db` (PRIMARY+REPLICA), `redis`, `kafka` —
  all **UP** using Vault-sourced credentials.
- Repo contains no plaintext credentials (verified by render + grep).
