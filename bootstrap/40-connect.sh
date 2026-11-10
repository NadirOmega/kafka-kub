#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"
check_context

# One distributed worker, internal topics with replication factor 1.
fresh_resource deployment/kafka-connect
ref="$(image_ref cp-kafka-connect "$CP_TAG")"
render_image "$ROOT/kafka-connect/02-deployment.yaml" "$OUT/kafka-connect.yaml" "$ref"
apply_manifest "$ROOT/kafka-connect/01-service.yaml"
apply_manifest "$OUT/kafka-connect.yaml"
wait_deployment kafka-connect
info "KAFKA_CONNECT_READY"
