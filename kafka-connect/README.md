# Kafka Connect — POC OpenShift

Un worker Kafka Connect **distributed**, utilisant l'image Confluent UBI 9 déjà transférée dans le registre interne. Service `ClusterIP` uniquement (`kafka-connect:8083`). Pas d'Operator, Route, PVC propre ni nouveaux NetworkPolicies.

La configuration fait créer automatiquement trois topics Kafka compactés `kafka-connect-poc-configs` (1 partition), `kafka-connect-poc-offsets` (3 partitions), et `kafka-connect-poc-status` (3 partitions), avec réplication **1** (POC mono-broker seulement). Leurs noms et `CONNECT_GROUP_ID` doivent rester stables sur les redémarrages. L'API reste disponible même avec zéro connecteur installé.

## Déployer (depuis la racine du dépôt)

```bash
git pull --ff-only
oc apply -f kafka-connect/ -n midlleware
oc rollout status deployment/kafka-connect -n midlleware --timeout=180s
```

## Tester l'API sans exposition externe

Terminal 1 :
```bash
oc port-forward -n midlleware svc/kafka-connect 18083:8083
```

Terminal 2 :
```bash
curl -fsS http://127.0.0.1:18083/connectors
curl -fsS http://127.0.0.1:18083/connector-plugins
```

Attendu : `[]` pour les connecteurs si aucun n'a été créé. La liste des plugins dépend de ce qui est réellement inclus dans l'image.

## Points à valider

- **Statut non testé sur cluster** : manifest versionné, pas encore confirmé Ready.
- L'image est référencée par **tag** tant que son digest interne n'est pas fourni ; après vérification du pull, figer la référence `@sha256:...` dans Git.
- Converters JSON sans Schema Registry pour le premier smoke test. Pour Avro/Protobuf, configurer les converters et l'URL `http://schema-registry:8081` lors d'une étape distincte, avec plugins validés.
- Pour la production, RF=3, plusieurs workers et hostname REST accessible entre workers, politiques de sécurité, TLS, sondes et dimensionnement réévalués.
- Ne pas renommer les trois topics internes ou le groupe dans une plateforme déjà utilisée.

Sources :
- https://docs.confluent.io/platform/current/installation/docker/config-reference.html
- https://docs.confluent.io/platform/8.4/connect/userguide.html
