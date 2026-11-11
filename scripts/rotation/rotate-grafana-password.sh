#!/usr/bin/env bash
# Rotate the Grafana admin password: Vault -> ESO -> k8s Secret -> restart grafana.
# Usage: NS=hyperscale ./rotate-grafana-password.sh
source "$(dirname "$0")/common.sh"

NEW=$(gen_password)
echo "== Rotating grafana admin password"

echo "-- updating Vault"
vault_cmd "vault kv patch secret/hyperscale/platform grafanaPassword='$NEW'"

echo "-- waiting for ESO to sync local-platform-credentials"
wait_secret_key local-platform-credentials grafana-password "$NEW"

echo "-- restarting grafana"
kubectl delete pod -l local-component=grafana -n "$NS" --wait=true --timeout=120s

echo "-- verifying"
kubectl get secret local-platform-credentials -n "$NS" -o jsonpath='{.data.grafana-password}' | base64 -d | grep -q "$NEW" \
  && echo "OK: grafana admin password is '$NEW' (log in as admin)"
