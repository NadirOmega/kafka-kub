#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"
check_context
need openssl

# Login form is mandatory before any external Route.
fresh_resource deployment/kafka-ui
[[ "$(oc get secret kafbat-ui-auth -n "$NS" -o name 2>/dev/null || true)" == "" ]] || die "kafbat-ui-auth already exists; won't overwrite credentials"
PASSWORD="$(openssl rand -hex 20)"
oc create secret generic kafbat-ui-auth -n "$NS" \
  --from-literal=username=admin --from-literal="password=$PASSWORD" >/dev/null
unset PASSWORD
ref="$(image_ref kafbat-ui "$UI_TAG")"
render_image "$ROOT/kafka-ui/02-deployment.yaml" "$OUT/kafbat.yaml" "$ref"
apply_manifest "$ROOT/kafka-ui/01-service.yaml"
apply_manifest "$OUT/kafbat.yaml"
wait_deployment kafka-ui
info "KAFBAT_READY: username admin; password stored ONLY in Secret kafbat-ui-auth"
info "Retrieve credentials securely using OpenShift Secret access; do not commit or paste them in logs."
