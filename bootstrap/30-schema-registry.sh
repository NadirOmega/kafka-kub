#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"
check_context

# Deploy Schema Registry, storing schemas in Kafka _schemas (RF=1 for POC).
fresh_resource deployment/schema-registry
ref="$(image_ref cp-schema-registry "$CP_TAG")"
render_image "$ROOT/schema-registry/02-deployment.yaml" "$OUT/schema-registry.yaml" "$ref"
apply_manifest "$ROOT/schema-registry/01-service.yaml"
apply_manifest "$OUT/schema-registry.yaml"
wait_deployment schema-registry
info "SCHEMA_REGISTRY_READY"
