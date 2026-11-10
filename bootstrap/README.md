# Bootstrap — installation à neuf Kafka OpenShift

Scripts Bash séparés par aspect fonctionnel, destinés à **un nouveau POC**, pas à un upgrade ni au POC déjà actif. Namespace cible fixé à **`midlleware`** dans les YAML. Ne pas relancer ces scripts sur des ressources existantes : les installateurs refusent de remplacer Kafka ou les Deployments déjà présents.

## Installation neuve

Depuis le dossier racine du dépôt :

```bash
oc project midlleware
bash bootstrap/00-preflight.sh
bash bootstrap/10-images.sh
bash bootstrap/20-kafka.sh
bash bootstrap/30-schema-registry.sh
bash bootstrap/40-connect.sh
bash bootstrap/50-rest-proxy.sh
bash bootstrap/60-kafbat.sh
bash bootstrap/90-tests.sh
```

Ou simplement `bash bootstrap/install-all.sh` (étapes 00→60), puis `bash bootstrap/90-tests.sh`.

| Script | Fonction | Requis |
| --- | --- | --- |
| `00-preflight.sh` | outils, permissions, StorageClass gp3, absence StatefulSet/PVC existant | Oui |
| `10-images.sh` | mirror Skopeo Docker Hub → registre OpenShift, tags 8.4.0-1-ubi9 + Kafbat | Oui |
| `20-kafka.sh` | Cluster ID neuf dans Secret, Kafka KRaft, PVC gp3, Service bootstrap/headless | Oui |
| `30-schema-registry.sh` | Service + Deployment Schema Registry | Oui |
| `40-connect.sh` | Kafka Connect distributed, 1 worker | Oui |
| `50-rest-proxy.sh` | REST Proxy API HTTP interne | Oui |
| `60-kafbat.sh` | Kafbat avec login local généré, Service interne | Oui |
| `65-kafbat-route.sh` | Route HTTPS **facultative**, login exigé | Option |
| `70-external-tls.sh` | Route passthrough + listener natif Kafka mTLS | Option |
| `90-tests.sh` | Kafka, Schema Registry, Connect et REST Proxy + test TLS optionnel | Oui |
| `install-all.sh` | enchaîne l'installation coeur 00→60 | Option |

Le build Java reste en pause : les dépendances Maven ne sont pas accessibles depuis Dev Spaces. ksqlDB n'a pas été déployé dans le POC validé.

## Prérequis

`oc`, `skopeo`, `python3`, `curl`, `openssl` et droits de créer Pods/Services/StatefulSets/PVC/Secrets/Deployments. Droits supplémentaires `routes` pour les étapes facultatives. Accès réseau à Docker Hub depuis Dev Spaces (sinon images déjà homologuées/mirroir interne). StorageClass `gp3` disponible.

Skopeo est configuré automatiquement avec `XDG_RUNTIME_DIR` et `REGISTRY_AUTH_FILE` sous `$HOME`. Si Docker Hub exige une connexion utilisateur, lancer `DOCKERHUB_LOGIN=1 bash bootstrap/10-images.sh`.

Les images sont injectées **par digest depuis l'ImageStream du namespace cible**, pour éviter l'erreur `ImagePullBackOff` rencontrée avec le tag. Le broker a son `cluster.id` généré **une seule fois** ; le secret `poc/02-cluster-id-secret.yaml` est historique et **ne fait pas partie du bootstrap**.

## Accès à Kafbat

L'installation crée `kafbat-ui-auth` avec `admin` et un mot de passe aléatoire dans le Secret. Pour afficher localement son mot de passe dans Dev Spaces (ne pas copier dans les logs) :

```bash
oc get secret kafbat-ui-auth -n midlleware \
  -o jsonpath='{.data.password}' | base64 -d; echo
```

L'accès UI interne se fait par Preview/port-forward. Pour activer facultativement une Route HTTPS, **seulement après vérification du formulaire** :

```bash
bash bootstrap/65-kafbat-route.sh
```

Supprimer l'exposition si besoin : `oc delete route kafka-ui -n midlleware`.

## Option Kafka natif externe TLS

Après installation du coeur et validation des tests :

```bash
bash bootstrap/70-external-tls.sh
TEST_EXTERNAL=1 bash bootstrap/90-tests.sh
```

Cela crée un certificat CA **local de 30 jours** dans `kafka-external/generated/` (ignoré par Git), un Secret TLS, le StatefulSet complet, une Route `passthrough` 443 et un Service 9094. Le listener interne Kafka 9092 n'est pas modifié. L'URL Route est injectée localement et **n'apparaît pas dans Git**.

Le script `70` **ne renouvelle pas** une CA ou un listener existant. Les renouvellements doivent être explicitement planifiés. Pour couper l'exposition externe : `oc delete route kafka-poc-external -n midlleware`.

## Tests

```bash
bash bootstrap/90-tests.sh
# Si la Route Kafka native et les certificats existent :
TEST_EXTERNAL=1 bash bootstrap/90-tests.sh
```

Le script écrit un nouveau topic et un nouveau sujet Schema Registry à chaque lancement ; il ne les supprime pas. Le Job client TLS éphémère et son Secret sont supprimés. Tests fonctionnels **dans OpenShift/Dev Spaces** ; cela ne prouve pas l'accessibilité Kafka native depuis le PC externe.

## Consignes de sécurité

- **Ne jamais** supprimer un PVC Kafka pour réparer une erreur de Cluster ID ou renouveler le TLS.
- Ne pas appliquer `poc/02-cluster-id-secret.yaml` ni `kafka-external/statefulset.template.yaml` directement.
- N'envoyer ni `generated/` ni les `.key`, `.p12`, `client.properties` vers Git.
- Éviter une Route Kafbat anonyme ou un listener Kafka externe sans authentification.
- Installation POC à 1 broker/controller, pas production HA. En production : PKI, RBAC/ACL, TLS interne, plusieurs brokers/controllers, monitoring et CI/CD.

Voir [HANDOFF.md](../HANDOFF.md) pour la chronologie et les incidents résolus.
