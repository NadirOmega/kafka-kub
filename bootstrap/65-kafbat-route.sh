#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"
check_context

# Opt-in HTTPS UI Route: do not expose a Kafbat Pod without LOGIN_FORM.
auth="$(oc get deployment kafka-ui -n "$NS" -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="AUTH_TYPE")].value}')"
[[ "$auth" == LOGIN_FORM ]] || die "Refusing public Route: Kafbat AUTH_TYPE is not LOGIN_FORM"
oc get secret kafbat-ui-auth -n "$NS" >/dev/null || die "Missing kafbat-ui-auth Secret"
wait_deployment kafka-ui
apply_manifest "$ROOT/kafka-ui/public/01-route.yaml"
oc get route kafka-ui -n "$NS" -o jsonpath='https://{.spec.host}{"\n"}'
info "UI Route created. Confirm login rejects anonymous access. Verify external reachability separately."
