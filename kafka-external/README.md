# Native Kafka from outside OpenShift via TLS passthrough

This folder contains only **staged** manifests for a Service and a TLS passthrough Route. **Do not apply them yet**: the Kafka broker has no listener on port 9094 and no client authentication configured. The existing POC is intentionally unchanged.

## Important: generated Route hostname

The hostname assigned by OpenShift must be included in all of these locations:

- Kafka `advertised.listeners` for `EXTERNAL`: `EXTERNAL://<actual-route-hostname>:443`.
- Kafka's server certificate **subjectAltName** (DNS) must include that exact hostname.
- The external client `bootstrap.servers=<actual-route-hostname>:443`. It uses `security.protocol=SSL`, **not HTTPS**.
- When scaling to multiple brokers, each broker requires its own externally reachable SNI hostname and corresponding Route/Service.

The externally visible port is `443`; inside the Pod, `EXTERNAL` listens on `9094`. The internal `INTERNAL://...:9092` and controller `CONTROLLER://...:9093` listeners must remain intact. OpenShift Routes with TLS passthrough send encrypted TCP through without termination, relying on client SNI and cluster router settings.

## Stage one: obtain the real hostname (no exposure yet)

The Service and Route can be **staged now only because the Kafka Pod does not listen on port 9094**. They expose no working Kafka socket in this state. Do not enable the 9094 listener until the certificate and client authentication are complete.

```bash
git pull --ff-only
oc apply -f kafka-external/01-service.yaml -f kafka-external/02-route.yaml -n midlleware
oc get route kafka-poc-external -n midlleware -o jsonpath='{.spec.host}{"\\n"}'
```

Take the real hostname and place it in the final broker `advertised.listeners` and certificate SAN, and then commit the broker's complete manifest. For this phase the backend port is still closed.

**The host cannot be guessed or templated as `localhost` or as an internal `.svc` DNS.**

## Status

- `01-service.yaml`, `02-route.yaml` prepared and committed.
- `poc/03-statefulset.yaml` intentionally untouched: no TLS cert, client mTLS credentials, hostname or authorization has yet been validated.
- Do not deploy the Route to an unauthenticated Kafka listener.
- mTLS client-authentication or equivalent approved SASL over TLS, proper SAN and CA trust, and ACL/security checks required before externally exposing.

## Test checklist after implementation

1. Verify route `Admitted=True`, and hostname is externally resolvable.
2. `openssl s_client -connect host:443 -servername host` should return the certificate (SNI mandatory).
3. An unauthorized client should **fail** authentication.
4. A trusted client should retrieve metadata showing `host:443` via `kcat -L` / `kafka-broker-api-versions` and produce/consume successfully.
5. Brokers' internal clients should continue working over port 9092.

Sources: https://docs.redhat.com/en/documentation/openshift_container_platform/4.19/html/ingress_and_load_balancing/routes ; https://docs.confluent.io/platform/8.4/security/authentication/mutual-tls/overview.html
