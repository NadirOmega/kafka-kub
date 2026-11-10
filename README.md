# Kafka sur OpenShift — sans Operator

Manifests Kubernetes du POC **Kafka KRaft** dans le namespace existant `midlleware`.

## État réel

- Image `cp-kafka:8.4.0-1-ubi9` copiée dans le registre OpenShift. **Pull réussi par digest** (observé dans les événements du Pod).
- `gp3` existe dans le cluster. Le bon fonctionnement du PVC et du broker reste à valider par un démarrage complet.
- Le **PVC préexistant** contient déjà un `cluster.id`. Le Secret `poc/02-cluster-id-secret.yaml` contient la **valeur relevée dans l'erreur Kafka** du 10/11/2026 (champ `but read`), et non un nouvel UUID.
- **Le broker n'est pas encore confirmé Ready**. Ne pas présenter ces manifests comme homologués production.

## Fichiers

- `poc/01-services.yaml` : bootstrap ClusterIP et service headless pour le DNS du Pod.
- `poc/02-cluster-id-secret.yaml` : Cluster ID *fixe*, identique à celui du PVC déjà formaté.
- `poc/03-statefulset.yaml` : un Pod Kafka (broker + controller), disque RWO gp3, image par digest immutable, DNS du namespace `midlleware`.

## Déploiement / correction du CrashLoopBackOff actuel

Dans Dev Spaces avec `oc` connecté au cluster :

```bash
git pull --ff-only
oc apply -f poc/ -n midlleware
oc delete pod kafka-poc-0 -n midlleware
oc get pod kafka-poc-0 -n midlleware -w
```

La suppression du **Pod uniquement** provoque sa recréation par le StatefulSet et recharge la valeur du Secret. **Ne supprimer ni PVC ni StatefulSet.** Si le Pod devient Ready, vérifier l'API Kafka :

```bash
oc exec -n midlleware kafka-poc-0 -- \
  kafka-broker-api-versions --bootstrap-server kafka-poc-bootstrap:9092 \
  >/dev/null && echo "KAFKA API OK"
```

Si le Pod reste en échec, consulter uniquement la fin du log précédent :

```bash
oc logs kafka-poc-0 -n midlleware --previous --tail=20
```

## Invariants / sécurité

- Le `cluster.id` du Secret doit **toujours** correspondre à `cluster.id` dans `meta.properties` sur le PVC. `--ignore-formatted` ne permet **pas** de faire démarrer Kafka avec un autre ID.
- Ne jamais régénérer le Cluster ID ni reformater/supprimer un PVC utilisé pour « corriger » une erreur d'identité.
- Un nouveau cluster **avec un nouveau PVC vide** doit recevoir son propre ID Kafka, généré **une seule fois** par `kafka-storage random-uuid`, puis conservé.
- Mode combiné et `PLAINTEXT` **uniquement pour ce POC interne isolé** ; pas de Route, Ingress, LoadBalancer ni NodePort.
- Pour la production, prévoir controllers et brokers dédiés, TLS/authentification, réplication, supervision, sauvegarde et tests de reprise.

## Références techniques

- [Confluent — configuration des images Docker Kafka](https://docs.confluent.io/platform/8.4/installation/docker/config-reference.html)
- [Confluent — configuration et formatage KRaft](https://docs.confluent.io/platform/8.4/kafka-metadata/config-kraft.html)
- [Confluent — script d'initialisation de l'image Kafka](https://github.com/confluentinc/kafka-images/blob/master/kafka/include/etc/confluent/docker/ensure)

## Correction du crash `lost+found` (10/11/2026)

Le PVC est formaté avec un système de fichiers qui contient `lost+found` à sa racine. Kafka refuse de le traiter comme un dossier de topic. Le StatefulSet monte **toujours le même PVC** en `/var/lib/kafka/data`, mais utilise `KAFKA_LOG_DIRS=/var/lib/kafka/data/kafka-logs`. Le formatteur Kafka crée ce sous-dossier et l'initialise avec le Cluster ID du Secret.

Ce changement de `log.dirs` est adapté **au POC récemment recréé**, sans données applicatives à conserver. Pour un cluster déjà chargé de données, changer `log.dirs` sans migration préalable peut rendre des partitions ou métadonnées existantes inaccessibles : ne pas l'appliquer aveuglément en production.

Après `git pull --ff-only` puis `oc apply -f poc/ -n midlleware`, le StatefulSet redémarre le Pod pour appliquer le nouvel environnement. Vérification ciblée :

```bash
oc get pod kafka-poc-0 -n midlleware
oc logs kafka-poc-0 -n midlleware --tail=15
```
