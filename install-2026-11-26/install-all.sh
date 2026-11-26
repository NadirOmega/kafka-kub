#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
# Fresh install only; reuse images in midlleware, no Skopeo.
for resource in sts/kafka-poc pvc/kafka-data-kafka-poc-0 \
 secret/kafka-poc-cluster-id secret/kafka-poc-external-tls secret/kafbat-ui-auth \
 deployment/schema-registry deployment/kafka-connect deployment/kafka-rest deployment/kafka-ui \
 svc/kafka-poc-bootstrap svc/kafka-poc-headless svc/kafka-poc-external \
 svc/schema-registry svc/kafka-connect svc/kafka-rest svc/kafka-ui \
 route/kafka-ui route/kafka-poc-external; do absent "$resource"; done
[[ "$(ocn auth can-i create routes)" == yes ]]
echo "01 - Kafka KRaft"
CLUSTER_ID="$(python3 -c 'import uuid,base64; print(base64.urlsafe_b64encode(uuid.uuid4().bytes).decode().rstrip("="))')"
ocn create secret generic kafka-poc-cluster-id --from-literal=CLUSTER_ID="$CLUSTER_ID"
deploy poc/01-services.yaml
deploy poc/03-statefulset.yaml
ocn rollout status sts/kafka-poc --timeout=300s
echo "02 - Schema Registry, Connect, REST Proxy"
for component in schema-registry kafka-connect kafka-rest; do
  deploy "$component/01-service.yaml"
  deploy "$component/02-deployment.yaml"
  ocn rollout status "deployment/$component" --timeout=300s
done
echo "03 - Kafbat UI"
ocn create secret generic kafbat-ui-auth --from-literal=username=admin \
  --from-literal=password="$(openssl rand -hex 20)"
deploy kafka-ui/01-service.yaml
deploy kafka-ui/02-deployment.yaml
ocn rollout status deployment/kafka-ui --timeout=300s
echo "04 - Internal Kafka metadata"
ocn exec kafka-poc-0 -- kafka-topics --bootstrap-server kafka-poc-bootstrap:9092 --list
echo "05 - External access and certificates"
TARGET_NS="$TARGET_NS" bash "$ROOT/install-2026-11-26/install-external.sh"
ocn get sts,deploy,pods,svc,route,pvc
echo "INSTALLATION_OK"
