#!/usr/bin/env bash
# Shared functions for a NEW Kafka POC installation.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NS="${NS:-midlleware}"
REG="${REG:-image-registry.openshift-image-registry.svc:5000}"
CP_TAG="${CP_TAG:-8.4.0-1-ubi9}"
UI_TAG="${UI_TAG:-a0aaba3}"
OUT="$ROOT/bootstrap/generated"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-$HOME/.local/run}"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export REGISTRY_AUTH_FILE="${REGISTRY_AUTH_FILE:-$HOME/.config/containers/auth.json}"

info() { printf '\n==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"; }
check_context() {
  need oc
  [[ "$(oc project -q)" == "$NS" ]] || die "Switch project first: oc project $NS"
}
image_ref() {
  local ref
  ref="$(oc get istag "$1:$2" -n "$NS" -o jsonpath='{.image.dockerImageReference}')"
  [[ "$ref" == *@sha256:* ]] || die "Missing digest for $1:$2"
  printf '%s' "$ref"
}
fresh_resource() {
  if oc get "$1" -n "$NS" >/dev/null 2>&1; then
    die "$1 already exists: fresh install refused to protect current data"
  fi
}
wait_deployment() {
  oc rollout status "deployment/$1" -n "$NS" --timeout=240s
}
apply_manifest() {
  oc apply -n "$NS" -f "$1"
}
render_image() {
  # Replace a single image: line in a full manifest, writing ONLY to ignored generated/.
  local source="$1" destination="$2" image="$3"
  need python3
  mkdir -p "$OUT"
  chmod 700 "$OUT"
  python3 - "$source" "$destination" "$image" <<'PY'
import pathlib,re,sys
src,dst,ref=pathlib.Path(sys.argv[1]),pathlib.Path(sys.argv[2]),sys.argv[3]
data=src.read_text()
data,count=re.subn(r'(?m)^(\s*image: )[^\n]+$',lambda m:m.group(1)+ref,data)
if count != 1: raise SystemExit("Expected exactly one container image line")
dst.write_text(data)
PY
}
