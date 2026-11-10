#!/usr/bin/env bash
set -euo pipefail

# Generate one local CA, a TLS server certificate for the *actual* OpenShift
# Route host, and a separate client certificate. No private keys in Git.
NS=midlleware
ROUTE=kafka-poc-external
HOST="$(oc get route "$ROUTE" -n "$NS" -o jsonpath='{.spec.host}')"
EXPECTED="kafka-poc-external-midlleware.apps.dev-app-hub.0k6e.p1.openshiftapps.com"
[[ -n "$HOST" && "$HOST" == "$EXPECTED" ]] || {
  echo "Unexpected Route host: $HOST (manifest expects: $EXPECTED)" >&2
  exit 1
}
command -v openssl >/dev/null
command -v keytool >/dev/null
if oc get secret kafka-external-tls -n "$NS" >/dev/null 2>&1; then
  echo "kafka-external-tls exists. Refusing to rotate certificates automatically." >&2
  exit 1
fi

OUT="$HOME/kafka-external-tls"
if [[ -e "$OUT" ]]; then
  echo "$OUT already exists. Refusing to overwrite keys." >&2
  exit 1
fi
umask 077
mkdir -m 700 "$OUT"
cd "$OUT"
PASSWORD="$(openssl rand -hex 16)"
printf %s "$PASSWORD" > store-password

# CA used to issue one broker certificate and one client certificate.
openssl req -x509 -newkey rsa:3072 -sha256 -nodes -days 30 \
  -subj "/CN=Kafka-POC-CA" -keyout ca.key -out ca.crt >/dev/null 2>&1

# Broker certificate matches the Route's TLS SNI hostname.
openssl req -new -newkey rsa:3072 -sha256 -nodes \
  -subj "/CN=$HOST" -keyout server.key -out server.csr >/dev/null 2>&1
printf 'subjectAltName=DNS:%s\nextendedKeyUsage=serverAuth\n' "$HOST" > server.ext
openssl x509 -req -sha256 -days 30 -in server.csr \
  -CA ca.crt -CAkey ca.key -CAcreateserial \
  -out server.crt -extfile server.ext >/dev/null 2>&1

# Client cert is needed because this listener requires mutual TLS.
openssl req -new -newkey rsa:3072 -sha256 -nodes \
  -subj "/CN=kafka-poc-client" -keyout client.key -out client.csr >/dev/null 2>&1
printf 'extendedKeyUsage=clientAuth\n' > client.ext
openssl x509 -req -sha256 -days 30 -in client.csr \
  -CA ca.crt -CAkey ca.key -CAcreateserial \
  -out client.crt -extfile client.ext >/dev/null 2>&1

# Kafka's Java SSL configuration uses PKCS12 keystore and truststore.
openssl pkcs12 -export -name kafka-server -in server.crt -inkey server.key \
  -certfile ca.crt -out kafka.keystore.p12 -passout "pass:$PASSWORD" >/dev/null 2>&1
keytool -importcert -noprompt -alias kafka-poc-ca -file ca.crt \
  -keystore kafka.truststore.p12 -storetype PKCS12 \
  -storepass "$PASSWORD" >/dev/null 2>&1

# Store only broker material in OpenShift, NEVER client.key / ca.key.
oc create secret generic kafka-external-tls -n "$NS" \
  --from-file=kafka.keystore.p12 \
  --from-file=kafka.truststore.p12 \
  --from-file=store-password

echo "TLS Secret created in namespace $NS"
echo "Client cert: $OUT/client.crt"
echo "Client key:  $OUT/client.key"
echo "CA cert:    $OUT/ca.crt"
echo "Do not commit these files. Certificates expire in 30 days."
