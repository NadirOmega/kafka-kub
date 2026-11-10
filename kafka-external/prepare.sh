#!/usr/bin/env bash
set -euo pipefail
umask 077

# 1. Resolve the real OpenShift Route hostname (never written to Git).
NS="${NS:-midlleware}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$ROOT/generated"
HOST="$(oc get route kafka-poc-external -n "$NS" -o jsonpath='{.spec.host}')"
[[ -n "$HOST" && "$HOST" =~ ^[a-zA-Z0-9.-]+$ ]] || { echo "Invalid/empty Route hostname"; exit 1; }
[[ ! -e "$OUT/ca.key" ]] || { echo "Existing local CA in $OUT: refuse to overwrite"; exit 1; }
for tool in oc openssl sed; do command -v "$tool" >/dev/null || { echo "Missing tool: $tool"; exit 1; }; done
mkdir -p "$OUT"
chmod 700 "$OUT"

# 2. Generate a short-lived local POC CA, broker certificate (SAN=Route hostname)
#    and a separate client certificate for mutual TLS.
openssl req -x509 -newkey rsa:3072 -sha256 -nodes -days 30 \
  -subj "/CN=Kafka POC local CA" -keyout "$OUT/ca.key" -out "$OUT/ca.crt" >/dev/null 2>&1
openssl req -new -newkey rsa:3072 -sha256 -nodes \
  -subj "/CN=$HOST" -keyout "$OUT/server.key" -out "$OUT/server.csr" >/dev/null 2>&1
printf 'subjectAltName=DNS:%s\nextendedKeyUsage=serverAuth\n' "$HOST" > "$OUT/server.ext"
openssl x509 -req -sha256 -days 30 -in "$OUT/server.csr" \
  -CA "$OUT/ca.crt" -CAkey "$OUT/ca.key" -CAcreateserial \
  -extfile "$OUT/server.ext" -out "$OUT/server.crt" >/dev/null 2>&1
openssl req -new -newkey rsa:3072 -sha256 -nodes \
  -subj "/CN=kafka-poc-client" -keyout "$OUT/client.key" -out "$OUT/client.csr" >/dev/null 2>&1
printf 'extendedKeyUsage=clientAuth\n' > "$OUT/client.ext"
openssl x509 -req -sha256 -days 30 -in "$OUT/client.csr" \
  -CA "$OUT/ca.crt" -CAkey "$OUT/ca.key" -CAcreateserial \
  -extfile "$OUT/client.ext" -out "$OUT/client.crt" >/dev/null 2>&1

# 3. PKCS12 keystores and a manifest-only Kubernetes Secret.
#    Secret is local and ignored by Git; nothing is applied automatically.
export KEYSTORE_PASSWORD="$(openssl rand -hex 20)"
export CLIENT_PASSWORD="$(openssl rand -hex 20)"
openssl pkcs12 -export -name kafka-poc-server \
  -inkey "$OUT/server.key" -in "$OUT/server.crt" -certfile "$OUT/ca.crt" \
  -out "$OUT/server.p12" -passout env:KEYSTORE_PASSWORD >/dev/null 2>&1
openssl pkcs12 -export -name kafka-poc-client \
  -inkey "$OUT/client.key" -in "$OUT/client.crt" -certfile "$OUT/ca.crt" \
  -out "$OUT/client.p12" -passout env:CLIENT_PASSWORD >/dev/null 2>&1
oc create secret generic kafka-poc-external-tls -n "$NS" \
  --from-file=server.p12="$OUT/server.p12" \
  --from-file=ca.crt="$OUT/ca.crt" \
  --from-literal=keystore-password="$KEYSTORE_PASSWORD" \
  --dry-run=client -o yaml > "$OUT/tls-secret.yaml"

# 4. Generate full StatefulSet YAML with injected advertised listener.
sed "s/EXTERNAL_HOST_PLACEHOLDER/$HOST/g" \
  "$ROOT/statefulset.template.yaml" > "$OUT/statefulset.yaml"

# 5. Local client properties for the native Kafka protocol.
cat > "$OUT/client.properties" <<EOF
security.protocol=SSL
ssl.truststore.type=PEM
ssl.truststore.location=$OUT/ca.crt
ssl.keystore.type=PKCS12
ssl.keystore.location=$OUT/client.p12
ssl.keystore.password=$CLIENT_PASSWORD
EOF
unset KEYSTORE_PASSWORD CLIENT_PASSWORD
printf 'Generated local files in: %s\n' "$OUT"
printf 'Route host resolved locally; not committed.\n'
printf 'Next (AFTER REVIEW): oc apply -n %s -f %s/tls-secret.yaml -f %s/statefulset.yaml\n' "$NS" "$OUT" "$OUT"
printf 'Then wait for kafka-poc-0 Ready; bootstrap for clients = ${HOST}:443 (see README).\n'
