#!/usr/bin/env bash
set -euo pipefail
umask 077

# Short-lived native Kafka smoke test via Route: independent from broker Pod.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NS="${NS:-midlleware}"
OUT="$ROOT/generated"
JOB="kafka-external-smoke"
SECRET="kafka-external-smoke-client"
TMP="$(mktemp -d)"
CREATED_SECRET=false
CREATED_JOB=false

cleanup() {
  if [[ "$CREATED_JOB" == true ]]; then
    oc delete job "$JOB" -n "$NS" --ignore-not-found --wait=true >/dev/null || true
  fi
  if [[ "$CREATED_SECRET" == true ]]; then
    oc delete secret "$SECRET" -n "$NS" --ignore-not-found >/dev/null || true
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT

for tool in oc sed grep; do command -v "$tool" >/dev/null || { echo "Missing: $tool" >&2; exit 1; }; done
[[ -s "$OUT/client.p12" && -s "$OUT/ca.crt" && -s "$OUT/client.properties" ]] || {
  echo "Missing client TLS material in generated/. Do not regenerate active certs." >&2
  exit 1
}
if oc get job "$JOB" -n "$NS" >/dev/null 2>&1 || oc get secret "$SECRET" -n "$NS" >/dev/null 2>&1; then
  echo "A previous smoke Job or Secret exists: stop to avoid overwriting it." >&2
  exit 1
fi

HOST="$(oc get route kafka-poc-external -n "$NS" -o jsonpath='{.spec.host}')"
[[ -n "$HOST" && "$HOST" =~ ^[a-zA-Z0-9.-]+$ ]] || { echo "Invalid Route host" >&2; exit 1; }
IMAGE="$(oc get pod kafka-poc-0 -n "$NS" -o jsonpath='{.spec.containers[0].image}')"
[[ "$IMAGE" == *cp-kafka@sha256:* ]] || { echo "Expected deployed cp-kafka image by digest" >&2; exit 1; }

# Convert local certificate paths to paths inside the separate test Pod.
sed "s|$OUT/|/etc/kafka/client/|g" "$OUT/client.properties" > "$TMP/client.properties"
grep -q '^ssl.keystore.location=/etc/kafka/client/client.p12$' "$TMP/client.properties" || {
  echo "Client properties path is unexpected; abort." >&2; exit 1;
}

# Create ephemeral secret without printing keys or credentials.
oc create secret generic "$SECRET" -n "$NS" \
  --from-file=client.p12="$OUT/client.p12" \
  --from-file=ca.crt="$OUT/ca.crt" \
  --from-file=client.properties="$TMP/client.properties" \
  --dry-run=client -o yaml | oc apply -n "$NS" -f - >/dev/null
CREATED_SECRET=true

# Use a NEW topic to make the producer-consumer assertion deterministic.
TOPIC="external-smoke-$(date +%s)"
cat <<EOF | oc apply -n "$NS" -f - >/dev/null
apiVersion: batch/v1
kind: Job
metadata:
  name: $JOB
  namespace: $NS
spec:
  backoffLimit: 0
  activeDeadlineSeconds: 150
  template:
    spec:
      restartPolicy: Never
      enableServiceLinks: false
      containers:
        - name: kafka-client
          image: $IMAGE
          command:
            - /bin/bash
            - -ec
            - |
              set -euo pipefail
              CFG=/etc/kafka/client/client.properties
              BOOTSTRAP="$HOST:443"
              TOPIC="$TOPIC"
              kafka-topics --bootstrap-server "\$BOOTSTRAP" --command-config "\$CFG" --create --topic "\$TOPIC" --partitions 1 --replication-factor 1
              printf 'EXTERNAL_NATIVE_TLS_OK\n' | kafka-console-producer --bootstrap-server "\$BOOTSTRAP" --producer.config "\$CFG" --topic "\$TOPIC"
              kafka-console-consumer --bootstrap-server "\$BOOTSTRAP" --consumer.config "\$CFG" --topic "\$TOPIC" --from-beginning --max-messages 1 --timeout-ms 30000 | grep -x EXTERNAL_NATIVE_TLS_OK
              echo "NATIVE_KAFKA_443_OK"
          volumeMounts:
            - name: client-tls
              mountPath: /etc/kafka/client
              readOnly: true
          resources:
            requests:
              cpu: 100m
              memory: 256Mi
            limits:
              cpu: "1"
              memory: 1Gi
      volumes:
        - name: client-tls
          secret:
            secretName: $SECRET
            defaultMode: 0444
EOF
CREATED_JOB=true

if ! oc wait -n "$NS" --for=condition=complete "job/$JOB" --timeout=160s; then
  oc logs -n "$NS" "job/$JOB" --tail=25 || true
  exit 1
fi
oc logs -n "$NS" "job/$JOB" --tail=10
echo "Smoke test done; temporary Job and credentials will be deleted."
