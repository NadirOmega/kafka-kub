#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"
check_context
need python3

# Protect existing KRaft identity and PVC: this script is fresh-install ONLY.
fresh_resource sts/kafka-poc
fresh_resource pvc/kafka-data-kafka-poc-0
fresh_resource secret/kafka-poc-cluster-id

# Generate a fresh 22-character URL-safe Kafka cluster ID once.
CLUSTER_ID="$(python3 -c 'import uuid,base64; print(base64.urlsafe_b64encode(uuid.uuid4().bytes).decode().rstrip("="))')"
[[ -n "$CLUSTER_ID" ]] || die "Failed to generate cluster ID"

# Create the cluster ID Secret, not a tracked YAML containing an old POC ID.
oc create secret generic kafka-poc-cluster-id \
  -n "$NS" --from-literal="CLUSTER_ID=$CLUSTER_ID" >/dev/null

# Use the exact digest mirrored to THIS cluster, not an old hardcoded digest.
ref="$(image_ref cp-kafka "$CP_TAG")"
render_image "$ROOT/poc/03-statefulset.yaml" "$OUT/kafka-internal.yaml" "$ref"
apply_manifest "$ROOT/poc/01-services.yaml"
apply_manifest "$OUT/kafka-internal.yaml"
oc rollout status sts/kafka-poc -n "$NS" --timeout=300s
oc wait -n "$NS" --for=condition=Ready pod/kafka-poc-0 --timeout=120s
info "KAFKA_READY"
