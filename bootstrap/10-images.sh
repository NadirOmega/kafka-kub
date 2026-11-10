#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"
check_context
need skopeo

# Skopeo credentials and runtime files belong to the user, not /run/containers.
mkdir -p "$XDG_RUNTIME_DIR" "$(dirname "$REGISTRY_AUTH_FILE")"
chmod 700 "$XDG_RUNTIME_DIR"
if [[ "${DOCKERHUB_LOGIN:-0}" == 1 ]]; then
  skopeo login --authfile "$REGISTRY_AUTH_FILE" docker.io
fi
oc whoami -t | skopeo login --authfile "$REGISTRY_AUTH_FILE" \
  -u "$(oc whoami)" --password-stdin "$REG"

# Mirror Confluent components straight to the OpenShift registry (no TAR).
for image in cp-kafka cp-schema-registry cp-kafka-connect cp-kafka-rest; do
  info "Mirroring $image:$CP_TAG"
  skopeo --insecure-policy copy \
    --src-authfile "$REGISTRY_AUTH_FILE" --dest-authfile "$REGISTRY_AUTH_FILE" \
    "docker://docker.io/confluentinc/$image:$CP_TAG" \
    "docker://$REG/$NS/$image:$CP_TAG"
  image_ref "$image" "$CP_TAG" >/dev/null
done

# Kafbat UI: official non-UBI image, allowed ONLY as POC exception.
info "Mirroring Kafbat UI $UI_TAG (NOT UBI)"
skopeo --insecure-policy copy \
  --src-authfile "$REGISTRY_AUTH_FILE" --dest-authfile "$REGISTRY_AUTH_FILE" \
  "docker://docker.io/kafbat/kafka-ui:$UI_TAG" \
  "docker://$REG/$NS/kafbat-ui:$UI_TAG"
image_ref kafbat-ui "$UI_TAG" >/dev/null
info "IMAGES_OK"
