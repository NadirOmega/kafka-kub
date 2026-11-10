#!/usr/bin/env bash
set -euo pipefail

# Re-render only the manifest from the existing certificate and the Route DNS.
# No certificate regeneration, no Secret changes, no oc apply.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$ROOT/generated"
NS="${NS:-midlleware}"

for tool in oc openssl sed; do
  command -v "$tool" >/dev/null || { echo "Missing: $tool" >&2; exit 1; }
done

[[ -s "$OUT/server.crt" && -s "$OUT/client.p12" && -s "$OUT/tls-secret.yaml" ]] || {
  echo "Missing TLS files: run prepare.sh once, or restore the original generated/ folder." >&2
  exit 1
}
HOST="$(oc get route kafka-poc-external -n "$NS" -o jsonpath='{.spec.host}')"
[[ -n "$HOST" && "$HOST" =~ ^[a-zA-Z0-9.-]+$ ]] || { echo "Invalid Route host" >&2; exit 1; }
openssl x509 -in "$OUT/server.crt" -noout -checkhost "$HOST" | grep -q 'does match' || {
  echo "Certificate SAN does not match current Route host. Do not reuse this certificate." >&2
  exit 1
}

umask 077
sed "s/EXTERNAL_HOST_PLACEHOLDER/$HOST/g" "$ROOT/statefulset.template.yaml" > "$OUT/statefulset.yaml"
echo "Manifest refreshed locally; no broker resource changed."
