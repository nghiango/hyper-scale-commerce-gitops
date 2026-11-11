# Password Rotation Runbook

How to rotate each credential in this environment. The chain is always:

```
vault kv (source of truth) → ESO syncs k8s Secret (~1m) → pods read at startup
```

Only the middle step is automatic — **pods must be restarted to pick up new
values**, and Postgres additionally needs the password changed inside the
database itself.

Prereq for all commands:

```bash
export VAULT_CMD='kubectl exec vault-0 -n hyperscale -c vault -- sh -c'
ROOT='export VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=$(awk "/Initial Root Token/{print \$NF}" /vault/data/init.json);'
```

Generate a fresh password:

```bash
NEW=$(head -c 24 /dev/urandom | base64 | tr -d '\n' | tr '+/' '-_')
```

---

## Redis (`secret/hyperscale/redis` → `redis-secret` → key `redis-password`)

Consumers: `redis-0` (server `--requirepass`), `redis-exporter`, `app`,
`order-query`.

```bash
# 1. Rotate in Vault
kubectl exec vault-0 -n hyperscale -c vault -- sh -c \
  "$ROOT vault kv patch secret/hyperscale/redis password='$NEW'"

# 2. Wait for ESO sync (<= 1m), verify
kubectl get externalsecret redis-secret -n hyperscale   # READY=True

# 3. Restart server FIRST, then clients
kubectl delete pod redis-0 -n hyperscale --wait
kubectl rollout restart deploy app order-query -n hyperscale
```

Verify:

```bash
kubectl exec redis-0 -n hyperscale -c redis -- sh -c \
  'redis-cli -a "$REDIS_PASSWORD" ping'          # PONG
kubectl rollout status deploy/app -n hyperscale
```

> No DB-side step needed — Redis auth is per-process from env.

## Postgres (`secret/hyperscale/postgres` → `postgres-credentials` → keys `password`, `replicator-password`)

Consumers: `postgres-ha-0..2` (Patroni), `pgbackrest-backup` CronJob, `app`,
`order-query`. **Also requires in-database rotation** — `pgdata` keeps the
password from `initdb`/`ALTER USER`, it does not follow the secret.

```bash
# 1. Rotate in Vault (both keys — do them together)
kubectl exec vault-0 -n hyperscale -c vault -- sh -c \
  "$ROOT vault kv put secret/hyperscale/postgres password='$NEW' replicatorPassword='$RNEW'"

# 2. Wait for ESO sync
kubectl get externalsecret postgres-credentials -n hyperscale

# 3. Rotate inside the DB FIRST (while old connections still work).
#    NOTE: the app authenticates as the 'hyperscale' role, not 'postgres'.
kubectl exec postgres-ha-0 -n hyperscale -- sh -c \
  "PGPASSWORD='<OLD password>' psql -U postgres -h localhost -c \
   \"ALTER USER postgres WITH PASSWORD '$NEW'; \
     ALTER USER replicator WITH PASSWORD '$RNEW'; \
     ALTER USER hyperscale WITH PASSWORD '$NEW';\""

# 4. Restart consumers
kubectl delete pod postgres-ha-0 postgres-ha-1 postgres-ha-2 -n hyperscale
kubectl rollout restart deploy app order-query -n hyperscale
```

Verify:

```bash
kubectl exec postgres-ha-0 -n hyperscale -- sh -c \
  "PGPASSWORD='$NEW' psql -U postgres -h localhost -tc 'select 1'"
kubectl exec -n hyperscale deploy/app -- wget -qO- \
  http://localhost:8080/actuator/health | grep -o '"db":{[^}]*"status":"UP"' | head -1
```

> If a pod restarts between steps 2 and 3 it will fail auth until step 3
> completes — brief errors are expected; do step 3 promptly.

## Grafana (`secret/hyperscale/platform` → `local-platform-credentials` → key `grafana-password`)

Consumers: `grafana` pod only (`GF_SECURITY_ADMIN_PASSWORD`).

```bash
# 1. Rotate in Vault
kubectl exec vault-0 -n hyperscale -c vault -- sh -c \
  "$ROOT vault kv patch secret/hyperscale/platform grafanaPassword='$NEW'"

# 2. Wait for ESO sync, then restart grafana
kubectl get externalsecret local-platform-credentials -n hyperscale
kubectl delete pod -l app.kubernetes.io/component=grafana -n hyperscale
```

Verify: log in at the Grafana UI with `admin` / `$NEW`.

---

## Quick reference — what happens if you forget a step

| If you... | Symptom |
|---|---|
| Rotate Vault only | ESO updates the Secret, but pods keep old env values — everything still works until a pod restarts, then auth failures |
| Skip `ALTER USER` (postgres) | After restart: `FATAL: password authentication failed` on app/replicas/backup |
| Restart clients before redis | Pods get new password while server still has old → Redis auth errors until redis restarts |
| Rotate during a Patroni failover | Leader may move; re-run `ALTER USER` check on whichever pod is primary (`postgres-ha-primary` Service now tracks it) |

## Notes / future improvements

- No automation restarts pods today. Adding stakater/Reloader with
  `reloader.stakater.com/auto: "true"` annotations on the Deployments/
  StatefulSets would automate step "restart consumers" — but **not** the
  postgres `ALTER USER` step, which needs an operator or a rotation Job.
- `refreshInterval: 1m` on each ExternalSecret controls propagation latency.
- Vault root token + unseal key live in `/vault/data/init.json` on the
  `vault-data-vault-0` PVC — treat as privileged.
