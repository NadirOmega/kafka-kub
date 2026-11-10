# REST Proxy — OpenShift POC

Image `cp-kafka-rest:8.4.0-1-ubi9` déjà copiée dans le registre interne, Service `ClusterIP` sur `kafka-rest:8082`, connexion au broker `kafka-poc-bootstrap:9092` et à Schema Registry `http://schema-registry:8081`.

Pas de Route, LoadBalancer, Ingress ni NetworkPolicy supplémentaire. POC interne en HTTP/PLAINTEXT ; pas de sécurisation prod.

## Déployer

Depuis la racine de `kafka-kub` :

```bash
git pull --ff-only
oc apply -n midlleware -f kafka-rest/
oc rollout status deployment/kafka-rest -n midlleware --timeout=180s
```

## Test HTTP via port-forward

Terminal 1 :

```bash
oc port-forward -n midlleware svc/kafka-rest 18082:8082
```

Terminal 2 :

```bash
# Voir les clusters détectés (API v3 standalone)
curl -fsS http://127.0.0.1:18082/v3/clusters
# Produire un message JSON dans le topic déjà créé test-kafka (API v2)
curl -fsS -X POST http://127.0.0.1:18082/topics/test-kafka \
  -H 'Content-Type: application/vnd.kafka.json.v2+json' \
  -H 'Accept: application/vnd.kafka.v2+json' \
  --data '{"records":[{"value":{"source":"rest-proxy","message":"REST_PROXY_OK"}}]}'
# Lire depuis Kafka (attention : topic contenant éventuellement d'autres messages)
oc exec -n midlleware kafka-poc-0 -- kafka-console-consumer \
  --bootstrap-server kafka-poc-bootstrap:9092 \
  --topic test-kafka --from-beginning --timeout-ms 10000
```

La réponse POST doit inclure les offsets des enregistrements, sans erreur, et le consumer doit afficher `REST_PROXY_OK`. Le test sera réellement validé **sur le cluster**, pas par le seul rollout.

## Notes

- L'image est encore référencée par tag ; la remplacer dans le dépôt par le digest interne **après contrôle** si nécessaire, sans `oc set image` manuel.
- `enableServiceLinks: false` empêche l'injection de `KAFKA_REST_PORT` par le Service Kubernetes, tout en conservant sa résolution DNS.
- La sonde utilise l'endpoint REST Proxy standalone v3 `/v3/clusters` : si la réponse n'est pas HTTP 2xx, examiner le code avant de changer la configuration.
- En prod : TLS, authentification, politiques d'accès, plusieurs réplicas et tests de résistance sont nécessaires.

Documentation : https://docs.confluent.io/platform/8.4/kafka-rest/api.html
