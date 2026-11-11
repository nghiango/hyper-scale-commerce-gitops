#!/usr/bin/env bash
# Rotate Postgres passwords: Vault -> ESO -> ALTER USER in the DB -> restart
# consumers. The in-DB roles must be rotated too — pgdata does not follow the
# secret. The app authenticates as the 'hyperscale' role, not 'postgres'.
# Usage: NS=hyperscale ./rotate-postgres-password.sh
source "$(dirname "$0")/common.sh"

NEW=$(gen_password)
RNEW=$(gen_password)
OLD=$(kubectl get secret postgres-credentials -n "$NS" -o jsonpath='{.data.password}' | base64 -d)

echo "== Rotating postgres passwords"

echo "-- updating Vault"
vault_cmd "vault kv put secret/hyperscale/postgres password='$NEW' replicatorPassword='$RNEW'"

echo "-- waiting for ESO to sync postgres-credentials"
wait_secret_key postgres-credentials password "$NEW"

echo "-- rotating roles inside the database (old password still valid here)"
LEADER=$(kubectl get endpoints postgres-ha-primary -n "$NS" -o jsonpath='{.subsets[0].addresses[0].targetRef.name}')
LEADER=${LEADER:-postgres-ha-0}
kubectl exec "$LEADER" -n "$NS" -- sh -c \
  "PGPASSWORD='$OLD' psql -U postgres -h localhost -c \
   \"ALTER USER postgres WITH PASSWORD '$NEW'; \
     ALTER USER replicator WITH PASSWORD '$RNEW'; \
     ALTER USER hyperscale WITH PASSWORD '$NEW';\""

echo "-- restarting postgres pods and clients"
kubectl delete pod postgres-ha-0 postgres-ha-1 postgres-ha-2 -n "$NS" --wait=false
kubectl rollout restart deploy/app deploy/order-query -n "$NS" >/dev/null
kubectl rollout status statefulset/postgres-ha -n "$NS" --timeout=300s
kubectl rollout status deploy/app -n "$NS" --timeout=180s
kubectl rollout status deploy/order-query -n "$NS" --timeout=180s

echo "-- verifying"
kubectl exec "$LEADER" -n "$NS" -- sh -c "PGPASSWORD='$NEW' psql -U postgres -h localhost -tqAc 'select 1'" | grep -q 1 \
  && echo "OK: postgres auth works with the new password"
