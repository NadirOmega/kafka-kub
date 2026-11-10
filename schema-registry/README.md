# Schema Registry — POC (OpenShift)

Un `Deployment` Confluent `cp-schema-registry:8.4.0-1-ubi9` et un Service interne `schema-registry:8081` dans `midlleware`. Pas de Route, Ingress, NetworkPolicy nouvelle ni PVC dédié. Schémas conservés dans le topic Kafka compacté `_schemas` (facteur de réplication 1 pour le broker unique).

## Déploiement

```bash
git pull --ff-only
oc apply -n midlleware -f schema-registry/
oc rollout status -n midlleware deployment/schema-registry --timeout=180s
```

## Test ciblé

Depuis Dev Spaces, en utilisant le port-forward uniquement pour diagnostic :

```bash
oc port-forward -n midlleware svc/schema-registry 8081:8081
```

Puis, dans un **autre terminal** :

```bash
curl -fsS http://localhost:8081/subjects
```

Résultat attendu sur registre vide : `[]`. Contrôler aussi le topic interne :

```bash
oc exec -n midlleware kafka-poc-0 -- kafka-topics --bootstrap-server kafka-poc-bootstrap:9092 --describe --topic _schemas
```

## Limites

- L'ImageStream `cp-schema-registry:8.4.0-1-ubi9` a été déclaré importé, mais **son digest n'est pas accessible depuis GitHub** ; le YAML utilise encore son tag. Après confirmation du pull sur le cluster, relever `oc get istag cp-schema-registry:8.4.0-1-ubi9 -n midlleware -o jsonpath='{.image.dockerImageReference}'` et mettre à jour **le manifest Git** pour figer le digest.
- Le paramètre `SCHEMA_REGISTRY_HOST_NAME=schema-registry` vise ce POC monoréplique. Pour la HA il faudra des hostnames joignables par instance.
- Le `/subjects` teste l'API ; des tests de création/lecture de schéma et de redémarrage resteront nécessaires.
- L'image et les contraintes UID/SCC ne sont pas encore validées en exécution. Ce YAML est un candidat de déploiement, pas une preuve de fonctionnement.

Références : [Configuration Confluent](https://docs.confluent.io/platform/current/installation/docker/config-reference.html), [Schema Registry 8.4](https://docs.confluent.io/platform/8.4/schema-registry/installation/config.html).
