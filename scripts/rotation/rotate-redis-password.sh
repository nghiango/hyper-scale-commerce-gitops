#!/usr/bin/env bash
# Rotate the Redis password: Vault -> ESO -> k8s Secret -> restart consumers.
# Server (redis-0) restarts BEFORE clients or clients auth with the new
# password against a server still on the old one.
# Usage: NS=hyperscale ./rotate-redis-password.sh
source "$(dirname "$0")/common.sh"

NEW=$(gen_password)
echo "== Rotating redis password"

echo "-- updating Vault"
vault_cmd "vault kv patch secret/hyperscale/redis password='$NEW'"

echo "-- waiting for ESO to sync redis-secret"
wait_secret_key redis-secret redis-password "$NEW"

echo "-- restarting redis (server first)"
kubectl delete pod redis-0 -n "$NS" --wait=true --timeout=120s

echo "-- restarting clients (app, order-query)"
kubectl rollout restart deploy/app deploy/order-query -n "$NS" >/dev/null
kubectl rollout status deploy/app -n "$NS" --timeout=180s
kubectl rollout status deploy/order-query -n "$NS" --timeout=180s

echo "-- verifying"
kubectl exec redis-0 -n "$NS" -c redis -- sh -c 'redis-cli -a "$REDIS_PASSWORD" ping' | grep -q PONG \
  && echo "OK: redis auth works with the new password"
