#!/usr/bin/env bash
# Fresh installation only. Existing Kafka data and credentials must never be overwritten.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

EXTERNAL=0
UI=0
case "${1:-}" in
  --all) EXTERNAL=1; UI=1 ;;
  --external) EXTERNAL=1 ;;
  "") ;;
  *) echo "Usage: bash install-kafka.sh [--all|--external]"; exit 2 ;;
esac
[[ $# -le 1 ]] || exit 2
export NS=midlleware
oc project "$NS"
# Check absence explicitly: an API/RBAC failure must abort, not look like NotFound.
for resource in sts/kafka-poc pvc/kafka-data-kafka-poc-0 \
  secret/kafka-poc-cluster-id secret/kafka-poc-external-tls secret/kafbat-ui-auth \
  deployment/schema-registry deployment/kafka-connect deployment/kafka-rest deployment/kafka-ui \
  svc/kafka-poc-bootstrap svc/kafka-poc-headless svc/kafka-poc-external \
  svc/schema-registry svc/kafka-connect svc/kafka-rest svc/kafka-ui \
  route/kafka-poc-external route/kafka-ui; do
  existing="$(oc get "$resource" -n "$NS" --ignore-not-found -o name)"
  if [[ -n "$existing" ]]; then
    echo "STOP: $existing already exists. Fresh installation only." >&2
    exit 1
  fi
done
command -v openssl >/dev/null
if (( EXTERNAL )); then
  [[ ! -e kafka-external/generated ]] || {
    echo "STOP: existing local TLS directory; preserve it and review before installing." >&2; exit 1;
  }
  [[ "$(oc auth can-i create routes -n "$NS")" == yes ]]
  [[ "$(oc auth can-i create jobs -n "$NS")" == yes ]]
  [[ "$(oc auth can-i delete jobs -n "$NS")" == yes ]]
  [[ "$(oc auth can-i delete secrets -n "$NS")" == yes ]]
fi
step() {
  printf '\n===== %s =====\n' "$1"
  shift
  "$@"
}
step "01 - Preflight" bash bootstrap/00-preflight.sh
step "02 - Import images via Skopeo" bash bootstrap/10-images.sh
step "03 - Kafka KRaft, Services, Secret and PVC (poc/*.yaml)" bash bootstrap/20-kafka.sh
step "04 - Schema Registry (schema-registry/*.yaml)" bash bootstrap/30-schema-registry.sh
step "05 - Kafka Connect (kafka-connect/*.yaml)" bash bootstrap/40-connect.sh
step "06 - REST Proxy (kafka-rest/*.yaml)" bash bootstrap/50-rest-proxy.sh
step "07 - Kafbat UI with local login (kafka-ui/*.yaml)" bash bootstrap/60-kafbat.sh
step "08 - Internal smoke tests" env TEST_EXTERNAL=0 bash bootstrap/90-tests.sh
if (( EXTERNAL )); then
  step "09 - Kafka Route TLS passthrough, mTLS and full StatefulSet YAML" bash bootstrap/70-external-tls.sh
  step "10 - Native Kafka smoke test via Route :443" bash kafka-external/smoke-test.sh
fi
if (( UI )); then
  step "11 - Kafbat HTTPS Route (login required; verify anonymous access separately)" bash bootstrap/65-kafbat-route.sh
fi
step "12 - Final inventory" oc get sts,deploy,pods,svc,route,pvc -n "$NS"
echo "INSTALLATION_OK"
if (( EXTERNAL )); then
  echo "Client PEM files: kafka-external/generated/{ca.crt,client.crt,client.key}"
  echo "External workstation test: see kafka-python-test/README.md"
fi
