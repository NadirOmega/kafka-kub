#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"
check_context
need openssl

# Optional stage: activate native Kafka TLS/mTLS through an OpenShift Route.
# Only on an already installed INTERNAL-only Kafka POC, never on an active TLS deployment.
[[ -n "$(oc get sts kafka-poc -n "$NS" -o name 2>/dev/null || true)" ]] || die "Install Kafka first"
listeners="$(oc get sts kafka-poc -n "$NS" -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="KAFKA_LISTENERS")].value}')"
[[ "$listeners" != *EXTERNAL* ]] || die "EXTERNAL listener already configured; do not rotate TLS implicitly"
[[ ! -e "$ROOT/kafka-external/generated/ca.key" ]] || die "Local TLS CA exists: existing or partial setup. Do not regenerate automatically."
[[ "$(oc auth can-i create routes -n "$NS")" == yes ]] || die "Cannot create OpenShift Routes"

# The Route has no hostname in Git; OpenShift assigns one.
apply_manifest "$ROOT/kafka-external/01-service.yaml"
apply_manifest "$ROOT/kafka-external/02-route.yaml"

# Create short-lived POC CA and local complete StatefulSet with the real hostname.
bash "$ROOT/kafka-external/prepare.sh"
[[ -s "$ROOT/kafka-external/generated/tls-secret.yaml" && -s "$ROOT/kafka-external/generated/statefulset.yaml" ]] || die "TLS generation incomplete"

# Use the exact image digest mirrored for this installation, not an old environment's digest.
ref="$(image_ref cp-kafka "$CP_TAG")"
render_image "$ROOT/kafka-external/generated/statefulset.yaml" "$OUT/kafka-external.yaml" "$ref"
apply_manifest "$ROOT/kafka-external/generated/tls-secret.yaml"
apply_manifest "$OUT/kafka-external.yaml"
oc rollout status sts/kafka-poc -n "$NS" --timeout=300s

# Port open is a preliminary check; use kafka-external/smoke-test.sh for real Kafka+mTLS test.
oc exec -n "$NS" kafka-poc-0 -- bash -c 'echo > /dev/tcp/127.0.0.1/9094' >/dev/null
info "EXTERNAL_LISTENER_READY (mTLS :9094 via Route :443; test next)"
