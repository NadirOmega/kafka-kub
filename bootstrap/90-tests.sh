#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"
check_context
need curl
need grep
need date

# A non-destructive, repeatable API smoke test. Creates only named test Kafka topics
# and Schema Registry subjects; existing application data and PVCs remain untouched.
info "Checking deployments"
oc wait -n "$NS" --for=condition=Ready pod/kafka-poc-0 --timeout=120s >/dev/null
for name in schema-registry kafka-connect kafka-rest kafka-ui; do
  wait_deployment "$name"
done

TOPIC="bootstrap-smoke-$(date +%s)"
info "Kafka internal produce / consume: $TOPIC"
oc exec -n "$NS" kafka-poc-0 -- kafka-topics --bootstrap-server kafka-poc-bootstrap:9092 \
  --create --topic "$TOPIC" --partitions 1 --replication-factor 1 >/dev/null
printf 'INTERNAL_KAFKA_OK\n' | oc exec -i -n "$NS" kafka-poc-0 -- \
  kafka-console-producer --bootstrap-server kafka-poc-bootstrap:9092 --topic "$TOPIC"
oc exec -n "$NS" kafka-poc-0 -- kafka-console-consumer \
  --bootstrap-server kafka-poc-bootstrap:9092 --topic "$TOPIC" \
  --from-beginning --max-messages 1 --timeout-ms 20000 | grep -x INTERNAL_KAFKA_OK

# Port forwards are local to this Dev Spaces terminal; no public exposure required.
pids=()
cleanup() { for pid in "${pids[@]}"; do kill "$pid" 2>/dev/null || true; done; }
trap cleanup EXIT
for spec in 'schema-registry 18081 8081' 'kafka-connect 18083 8083' 'kafka-rest 18082 8082'; do
  read -r svc port target <<< "$spec"
  oc port-forward -n "$NS" "svc/$svc" "$port:$target" >/dev/null 2>&1 &
  pids+=("$!")
done
wait_http() {
  local url="$1" ok=0
  for attempt in {1..25}; do
    if curl --noproxy '*' -fsS "$url" >/dev/null 2>&1; then ok=1; break; fi
    sleep 1
  done
  [[ "$ok" == 1 ]] || die "No HTTP response at $url"
}
wait_http http://127.0.0.1:18081/subjects
wait_http http://127.0.0.1:18083/connectors
wait_http http://127.0.0.1:18082/v3/clusters

# Schema registration (REST API) with one new test subject.
info "Schema Registry API"
subject="bootstrap-smoke-$(date +%s)-value"
curl --noproxy '*' -fsS -X POST "http://127.0.0.1:18081/subjects/$subject/versions" \
  -H 'Content-Type: application/vnd.schemaregistry.v1+json' \
  --data '{"schema":"{\"type\":\"record\",\"name\":\"Smoke\",\"fields\":[{\"name\":\"id\",\"type\":\"int\"}]}"}' | grep -q '"id"'
echo "SCHEMA_REGISTRY_OK"

# Kafka Connect API: worker responds, connector list may legitimately be empty.
info "Kafka Connect API"
curl --noproxy '*' -fsS http://127.0.0.1:18083/connectors | grep -q '^\['
echo "CONNECT_API_OK"

# REST Proxy -> Kafka, then consume from Kafka native CLI.
info "REST Proxy -> Kafka topic"
curl --noproxy '*' -fsS -X POST "http://127.0.0.1:18082/topics/$TOPIC" \
  -H 'Content-Type: application/vnd.kafka.json.v2+json' \
  -H 'Accept: application/vnd.kafka.v2+json' \
  --data '{"records":[{"value":{"source":"rest-proxy","test":"REST_PROXY_OK"}}]}' | grep -q '"offsets"'
oc exec -n "$NS" kafka-poc-0 -- kafka-console-consumer \
  --bootstrap-server kafka-poc-bootstrap:9092 --topic "$TOPIC" \
  --from-beginning --max-messages 2 --timeout-ms 20000 | grep -q REST_PROXY_OK
echo "REST_PROXY_OK"

# Optional external test: separate Job using the existing local mTLS certificates.
if [[ "${TEST_EXTERNAL:-0}" == 1 ]]; then
  bash "$ROOT/kafka-external/smoke-test.sh"
fi
info "ALL_CORE_TESTS_OK"
