# Kafka Python external smoke test

Client Windows / VS Code, kafka-python, no venv or C++ build required.
Uses native Kafka over SSL with mTLS, not HTTPS, through the existing OpenShift Route.
No cluster deployment changes. Never regenerate the active CA for this test.

## Setup (PowerShell, from repository root)

```powershell
cd kafka-python-test
python -m pip install -r requirements.txt
Copy-Item config.example.json config.local.json
```

Edit config.local.json locally: set bootstrap_servers to the actual Route hostname:443 (no https://).
Get the hostname from an authenticated OpenShift terminal:
```bash
oc get route kafka-poc-external -n midlleware -o jsonpath='{.spec.host}{"\n"}'
```

Copy only ca.crt, client.crt and client.key from kafka-external/generated/ to certificates/ using an approved secure transfer. The existing prepare.sh generates all three in PEM already; no conversion needed. Do not copy ca.key, server.key, server.p12 or Secret manifests. Never commit credentials or the real endpoint. Check certificate expiration; the POC certificates were issued for 30 days.

## Run in order

```powershell
python test_connection.py
python smoke_test.py
```

First command checks DNS, TCP, TLS handshake and Kafka metadata without producing a message. A TLS handshake alone does not prove Kafka authorization. Second command creates a unique single-partition test topic (RF=1 for current POC), writes a unique message and verifies its exact value on consumption. Expected: NATIVE_KAFKA_443_OK. The topic is retained deliberately. Requires topic creation, write and read permissions.

Optional independent tests (use an existing authorized test topic):
```powershell
python producer.py --topic python-test --message "Hello Kafka"
python consumer.py --topic python-test
```
Consumer reads from earliest and exits after the first message; use smoke_test.py for an exact round-trip assertion.

DNS/TCP failure: check enterprise network and Route reachability. Kafka is raw TLS, not HTTP; an HTTP proxy alone may not support it. TLS failure: check CA, expiration, hostname SAN, client key and certificate. Do not disable hostname verification. Kafka metadata or authorization failure: check advertised listeners and broker permissions.

All scripts must be tested from the actual external workstation; no success is assumed until execution.
