#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

# Validate the target namespace, tooling and storage class.
check_context
for tool in skopeo python3 curl; do need "$tool"; done
oc get storageclass gp3 >/dev/null || die "StorageClass gp3 missing"
for kind in pods services secrets deployments statefulsets persistentvolumeclaims; do
  [[ "$(oc auth can-i create "$kind" -n "$NS")" == yes ]] || die "Missing create rights: $kind"
done

# Never run the from-scratch sequence over the existing Kafka cluster.
fresh_resource sts/kafka-poc
fresh_resource pvc/kafka-data-kafka-poc-0
info "PRECHECK_OK namespace=$NS storage=gp3, Kafka StatefulSet/PVC absent"
