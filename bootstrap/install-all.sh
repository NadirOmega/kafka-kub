#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# NEW, EMPTY NAMESPACE ONLY; not a reconcile/upgrade command.
# This intentionally does not create a public UI Route or external Kafka TLS.
for name in 00-preflight 10-images 20-kafka 30-schema-registry 40-connect 50-rest-proxy 60-kafbat; do
  printf '\n***** %s *****\n' "$name"
  bash "$ROOT/$name.sh"
done
printf '\nINSTALLATION_CORE_OK\n'
printf 'Run bash bootstrap/90-tests.sh to validate, then optional 70-external-tls.sh.\n'
