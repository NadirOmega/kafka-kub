#!/usr/bin/env bash
set -euo pipefail
umask 077
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
TARGET_NS="${TARGET_NS:-$(oc project -q)}"
[[ "$TARGET_NS" == "$(oc project -q)" ]] || { echo "Select target namespace with oc project first"; exit 1; }
[[ "$TARGET_NS" != midlleware ]] || { echo "STOP: source namespace protected"; exit 1; }
[[ "$TARGET_NS" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] || exit 1
ocn() { oc -n "$TARGET_NS" "$@"; }
deploy() {
  sed -e "s/namespace: midlleware/namespace: $TARGET_NS/g" \
      -e "s/\.midlleware\.svc/.$TARGET_NS.svc/g" "$1" | ocn apply -f -
}
absent() {
  local existing
  existing="$(ocn get "$1" --ignore-not-found -o name)"
  [[ -z "$existing" ]] || { echo "STOP: $existing already exists"; exit 1; }
}
for tool in oc sed openssl keytool python3; do command -v "$tool" >/dev/null || { echo "Missing $tool"; exit 1; }; done
