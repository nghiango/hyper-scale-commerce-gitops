# Shared helpers for the rotation scripts. Source this file, don't run it.
set -euo pipefail

NS="${NS:-hyperscale}"

# Run a vault CLI command inside the vault container with the root token.
vault_cmd() {
  kubectl exec vault-0 -n "$NS" -c vault -- sh -c \
    "export VAULT_ADDR=http://127.0.0.1:8200 \
           VAULT_TOKEN=\$(awk '/Initial Root Token/{print \$NF}' /vault/data/init.json); $*"
}

# Wait until a key inside a k8s Secret equals the expected value (ESO sync lag).
wait_secret_key() { # <secret> <key> <expected>
  local secret=$1 key=$2 expected=$3 tries=0
  until [ "$(kubectl get secret "$secret" -n "$NS" -o "jsonpath={.data.$key}" | base64 -d)" = "$expected" ]; do
    tries=$((tries+1)); [ "$tries" -gt 60 ] && { echo "TIMEOUT waiting for $secret/$key to sync"; return 1; }
    sleep 3
  done
}

gen_password() {
  head -c 24 /dev/urandom | base64 | tr -d '\n' | tr '+/' '-_'
}
