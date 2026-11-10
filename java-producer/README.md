# Producer Java — POC OpenShift

Client Java Apache Kafka `4.4.0` pour un broker Confluent Platform `8.4.x`, Java 17 (supporté). Produit dix messages avec `acks=all`, idempotence, clés uniques, et attend la confirmation serveur. Job terminé après publication.

## Build de l'image (sur environnement autorisé avec Maven + Docker/Podman)

```bash
cd java-producer
mvn -B -ntp -DskipTests package
podman build -f Containerfile -t kafka-java-producer:1.0.0 .
```

La base `registry.access.redhat.com/ubi9/openjdk-17-runtime` existe chez Red Hat, **mais son accès et son autorisation ne sont pas encore vérifiés sur ton environnement**. Si le proxy bloque l'accès, utiliser la base UBI 9 homologuée en miroir d'entreprise. Contrôler la compatibilité SCC/UID arbitraire avant exploitation.

## Transfert vers registre interne OpenShift

Depuis un poste pouvant atteindre le registre : pousser l'image vers la destination interne en utilisant la procédure approuvée par l'équipe plateforme. Si l'on est dans Dev Spaces, une option est de transférer un `docker-archive` puis de faire un `skopeo copy` vers `image-registry.openshift-image-registry.svc:5000/midlleware/kafka-java-producer:1.0.0`, en conservant les permissions de registre existantes.

**Ne pas déployer tant que l'image n'est pas visible dans l'ImageStream.** Après publication, relever le digest local et remplacer le tag de `job.yaml` par `@sha256:...` avant mise en production.

## Exécution

```bash
oc apply -f java-producer/job.yaml -n midlleware
oc wait -n midlleware --for=condition=complete job/kafka-java-producer-test --timeout=120s
oc logs -n midlleware job/kafka-java-producer-test
```

Pour réexécuter le Job, supprimer **uniquement le Job** (pas le PVC ou le broker), puis réappliquer.

Pour contrôler depuis Kafka :

```bash
oc exec -n midlleware kafka-poc-0 -- kafka-console-consumer \
  --bootstrap-server kafka-poc-bootstrap:9092 --topic test-kafka \
  --from-beginning --timeout-ms 10000
```

Note : ce Job ne dépend pas de Schema Registry (sérialisation String).
