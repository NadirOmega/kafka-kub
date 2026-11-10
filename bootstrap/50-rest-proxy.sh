#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"
check_context

# Kafka native remains internal; REST Proxy is a separate HTTP API on port 8082.
fresh_resource deployment/kafka-rest
ref="$(image_ref cp-kafka-rest "$CP_TAG")"
render_image "$ROOT/kafka-rest/02-deployment.yaml" "$OUT/kafka-rest.yaml" "$ref"
apply_manifest "$ROOT/kafka-rest/01-service.yaml"
apply_manifest "$OUT/kafka-rest.yaml"
wait_deployment kafka-rest
info "REST_PROXY_READY"
