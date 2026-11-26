#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
# Existing internal installation only. No PVC or cluster-ID modifications.
ocn rollout status sts/kafka-poc --timeout=300s
ocn rollout status deployment/kafka-ui --timeout=300s
listeners="$(ocn get sts kafka-poc -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="KAFKA_LISTENERS")].value}')"
[[ "$listeners" == 'INTERNAL://0.0.0.0:9092,CONTROLLER://0.0.0.0:9093' ]] || { echo "STOP: unexpected listeners or TLS already active"; exit 1; }
[[ "$(ocn get sts kafka-poc -o jsonpath='{.spec.replicas}')" == 1 ]] || { echo "STOP: single broker only"; exit 1; }
ocn get secret kafka-poc-cluster-id >/dev/null
ocn get pvc kafka-data-kafka-poc-0 >/dev/null
absent secret/kafka-poc-external-tls
absent route/kafka-poc-external
absent svc/kafka-poc-external
auth="$(ocn get deployment kafka-ui -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="AUTH_TYPE")].value}')"
[[ "$auth" == LOGIN_FORM ]] || { echo "STOP: Kafbat login required"; exit 1; }
ocn get secret kafbat-ui-auth >/dev/null
[[ "$(ocn auth can-i create routes)" == yes ]]
[[ "$(ocn auth can-i create secrets)" == yes ]]
# Separate private directory per namespace and execution; never overwrite old certificates.
BASE="$ROOT/install-2026-11-26/generated/$TARGET_NS"
mkdir -p "$BASE"
OUT="$BASE/$(date +%F_%H%M%S)"
mkdir -m 700 "$OUT"
export OUT
echo "01 - External service and TLS passthrough Route"
deploy kafka-external/01-service.yaml
deploy kafka-external/02-route.yaml
HOST="$(ocn get route kafka-poc-external -o jsonpath='{.spec.host}')"
[[ "$HOST" =~ ^[a-zA-Z0-9.-]+$ ]] || exit 1
echo "02 - Generate CA, server and client certificates"
DAYS="${CERT_DAYS:-30}"
[[ "$DAYS" =~ ^[1-9][0-9]*$ ]] || exit 1
openssl req -x509 -newkey rsa:3072 -nodes -sha256 -days "$DAYS" \
  -subj "/CN=Kafka POC local CA" -addext "basicConstraints=critical,CA:TRUE" \
  -addext "keyUsage=critical,keyCertSign,cRLSign" -keyout "$OUT/ca.key" -out "$OUT/ca.crt"
openssl req -new -newkey rsa:3072 -nodes -subj "/CN=kafka-poc-server" \
  -keyout "$OUT/server.key" -out "$OUT/server.csr"
printf 'subjectAltName=DNS:%s\nextendedKeyUsage=serverAuth\nbasicConstraints=CA:FALSE\n' "$HOST" > "$OUT/server.ext"
openssl x509 -req -sha256 -days "$DAYS" -in "$OUT/server.csr" -CA "$OUT/ca.crt" \
  -CAkey "$OUT/ca.key" -CAcreateserial -extfile "$OUT/server.ext" -out "$OUT/server.crt"
openssl req -new -newkey rsa:3072 -nodes -subj "/CN=kafka-poc-client" \
  -keyout "$OUT/client.key" -out "$OUT/client.csr"
printf 'extendedKeyUsage=clientAuth\nbasicConstraints=CA:FALSE\n' > "$OUT/client.ext"
openssl x509 -req -sha256 -days "$DAYS" -in "$OUT/client.csr" -CA "$OUT/ca.crt" \
  -CAkey "$OUT/ca.key" -CAserial "$OUT/ca.srl" -extfile "$OUT/client.ext" -out "$OUT/client.crt"
openssl verify -CAfile "$OUT/ca.crt" -purpose sslserver -verify_hostname "$HOST" "$OUT/server.crt"
openssl verify -CAfile "$OUT/ca.crt" -purpose sslclient "$OUT/client.crt"
echo "03 - PKCS12 and JKS stores"
export SERVER_PASS="$(openssl rand -hex 20)"
export CLIENT_PASS="$(openssl rand -hex 20)"
export TRUST_PASS="$(openssl rand -hex 20)"
for side in server client; do
  if [[ "$side" == server ]]; then pass=SERVER_PASS; else pass=CLIENT_PASS; fi
  openssl pkcs12 -export -name "kafka-poc-$side" -inkey "$OUT/$side.key" \
    -in "$OUT/$side.crt" -certfile "$OUT/ca.crt" -out "$OUT/$side.p12" -passout "env:$pass"
  keytool -importkeystore -noprompt -srckeystore "$OUT/$side.p12" -srcstoretype PKCS12 \
    -srcstorepass:env "$pass" -destkeystore "$OUT/$side-keystore.jks" -deststoretype JKS \
    -deststorepass:env "$pass" -destkeypass:env "$pass"
done
keytool -importcert -noprompt -alias kafka-ca -file "$OUT/ca.crt" \
  -keystore "$OUT/truststore.jks" -storetype JKS -storepass:env TRUST_PASS
printf 'server_keystore_password=%s\nclient_keystore_password=%s\nclient_key_password=%s\ntruststore_password=%s\n' \
  "$SERVER_PASS" "$CLIENT_PASS" "$CLIENT_PASS" "$TRUST_PASS" > "$OUT/passwords.txt"
printf '%s:443\n' "$HOST" > "$OUT/endpoint.txt"
cat > "$OUT/client.properties" <<EOF
security.protocol=SSL
ssl.truststore.type=PEM
ssl.truststore.location=$OUT/ca.crt
ssl.keystore.type=PKCS12
ssl.keystore.location=$OUT/client.p12
ssl.keystore.password=$CLIENT_PASS
EOF
cat > "$OUT/client-jks.properties" <<EOF
security.protocol=SSL
ssl.truststore.type=JKS
ssl.truststore.location=$OUT/truststore.jks
ssl.truststore.password=$TRUST_PASS
ssl.keystore.type=JKS
ssl.keystore.location=$OUT/client-keystore.jks
ssl.keystore.password=$CLIENT_PASS
ssl.key.password=$CLIENT_PASS
EOF
echo "04 - Deploy TLS Secret and full StatefulSet manifest"
ocn create secret generic kafka-poc-external-tls --from-file=server.p12="$OUT/server.p12" \
  --from-file=ca.crt="$OUT/ca.crt" --from-literal=keystore-password="$SERVER_PASS" \
  --dry-run=client -o yaml > "$OUT/tls-secret.yaml"
# Preserve the already running broker image (including its source namespace).
IMAGE="$(ocn get sts kafka-poc -o jsonpath='{.spec.template.spec.containers[0].image}')"
python3 - "$ROOT/kafka-external/statefulset.template.yaml" "$OUT/statefulset.yaml" "$TARGET_NS" "$HOST" "$IMAGE" <<'PY'
import pathlib,re,sys
src,dst,ns,host,image=sys.argv[1:]
s=pathlib.Path(src).read_text().replace("namespace: midlleware","namespace: "+ns).replace(".midlleware.svc","."+ns+".svc").replace("EXTERNAL_HOST_PLACEHOLDER",host)
s,n=re.subn(r"(?m)^(\s*image: )[^\n]+$",lambda m:m.group(1)+image,s)
if n!=1: raise SystemExit("Unexpected image line")
pathlib.Path(dst).write_text(s)
PY
ocn apply -f "$OUT/tls-secret.yaml"
ocn apply -f "$OUT/statefulset.yaml"
ocn rollout status sts/kafka-poc --timeout=300s
unset SERVER_PASS CLIENT_PASS TRUST_PASS
echo "05 - Native Kafka smoke test (temporary Job)"
# Reuse historical smoke script in a private temporary layout with dated certificates.
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cp kafka-external/smoke-test.sh "$TMP/smoke-test.sh"
mkdir "$TMP/generated"
cp "$OUT/client.p12" "$OUT/ca.crt" "$TMP/generated/"
sed "s|$OUT/|$TMP/generated/|g" "$OUT/client.properties" > "$TMP/generated/client.properties"
# Historical smoke script requires digest image. Resolve the running image ID if necessary.
# Its existing digest requirement is satisfied by the original internal installer.
NS="$TARGET_NS" bash "$TMP/smoke-test.sh"
echo "06 - Kafbat HTTPS Route"
deploy kafka-ui/public/01-route.yaml
ocn get routes
printf 'Kafka endpoint: %s:443\nCertificates: %s\n' "$HOST" "$OUT"
echo "EXTERNAL_INSTALL_OK (verify Windows reachability and Kafbat login separately)"
