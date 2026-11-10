# HANDOFF — Kafka OpenShift / KRaft (10 novembre 2026)

## 1. Objectif / contraintes

Construire sur OpenShift, dans le namespace exact **`midlleware`**, un POC Kafka **sans Operator et sans Strimzi**, avec manifests Kubernetes natifs et images principalement basées sur **UBI 9**. Registre interne OpenShift : `image-registry.openshift-image-registry.svc:5000`. Accès Dev Spaces distant. Exposition des APIs internes seulement, sauf Kafbat UI via Route HTTPS sécurisée par formulaire et Kafka natif via Route **TLS passthrough**.

Le namespace s'écrit **`midlleware`** (et non `middleware`). Pas d'hostname réel ni de clé privée Git. Le service interne Kafka utilise un Service headless pour l'adresse stable du broker, plus un ClusterIP bootstrap.

## 2. Architecture réellement testée

| Composant | Image | Kubernetes / accès | État |
| --- | --- | --- | --- |
| Kafka KRaft | `cp-kafka:8.4.0-1-ubi9` | StatefulSet `kafka-poc`, 1 broker/controller, PVC `gp3` 10 GiB | Démarré ; production et consommation testées |
| Schema Registry | `cp-schema-registry:8.4.0-1-ubi9` | Deployment + Service `schema-registry:8081` | API /subjects et schéma Avro testés |
| Kafka Connect | `cp-kafka-connect:8.4.0-1-ubi9` | Deployment worker distributed + Service `kafka-connect:8083` | REST /connectors et /connector-plugins testés ; aucun plugin métier déployé |
| REST Proxy | `cp-kafka-rest:8.4.0-1-ubi9` | Deployment + Service `kafka-rest:8082` | Production HTTP puis consommation Kafka testées |
| Kafbat UI | `kafbat/kafka-ui:a0aaba3` (Alpine, exception UBI temporaire) | Deployment + Service `kafka-ui:8080`, Route HTTPS avec `LOGIN_FORM` | Interface, brokers, topics, Registry et Connect vus via navigateur |
| Kafka externe | Même broker, `EXTERNAL:9094` SSL/mTLS | Service `kafka-poc-external:9094` + Route passthrough `:443` | TLS + API Kafka + Producer/Consumer testés **depuis un Pod** |
| Producer Java | Maven + image UBI 9 préparés | Job non opérationnel | **En pause** : Maven Central inaccessible dans Dev Spaces |
| ksqlDB | Non importé/déployé | — | Hors périmètre de la phase validée |

**Limite de validation :** l'accès Kafka natif `:443` **depuis le poste externe** n'a pas été prouvé ; le poste rencontrait une erreur DNS/proxy `502 notresolvable`. Le test fonctionnel a eu lieu à travers la Route **depuis OpenShift**. Le POC est **mono-broker** et le listener interne est en PLAINTEXT : il n'est pas homologué production.

## 3. Endpoints et configuration

- Bootstrap interne Kafka : `kafka-poc-bootstrap:9092` (ClusterIP)
- DNS stable du broker : `kafka-poc-0.kafka-poc-headless.midlleware.svc:9092` (headless)
- Controller KRaft : `:9093`
- Listener natif TLS externe : broker `:9094` ↔ Route OpenShift `:443` (SNI)
- Le hostname externe, attribué par OpenShift **sans `spec.host`**, est injecté localement dans `KAFKA_ADVERTISED_LISTENERS` et dans le **SAN du certificat serveur**.
- Auth mTLS client exigée sur EXTERNAL ; Secret broker `kafka-poc-external-tls`. Certificats CA POC auto-signés valables **30 jours**.
- Kafbat UI utilise `AUTH_TYPE=LOGIN_FORM` avec Secret `kafbat-ui-auth`, simple compte local ; pas de SSO/RBAC d'entreprise.
- `enableServiceLinks: false` dans les Deployments sensibles aux variables `*_PORT` injectées par OpenShift.

## 4. Incidents résolus, à ne pas reproduire

1. **ImagePullBackOff / authentication required** sur Kafka par tag : référence immuable `@sha256:` issue de l'ImageStream OpenShift, sans changement RBAC (le RoleBinding `system:image-pullers` et le pull Secret existaient).
2. **KRaft `Invalid cluster.id`** : le PVC contenait déjà un ID différent du Secret. Ne jamais changer le Cluster ID d'un PVC formaté ; notre nouvelle installation génère l'ID **une seule fois**.
3. **Kafka `lost+found`** : le dossier ext4 au sommet du PVC cassait la lecture des logs. `KAFKA_LOG_DIRS=/var/lib/kafka/data/kafka-logs`.
4. **Schema Registry CrashLoop** avec `PORT is deprecated` : `enableServiceLinks: false` empêche l'injection de `SCHEMA_REGISTRY_PORT`.
5. **TLS externe :9094 absent** : plusieurs tentatives avaient conservé l'ancienne configuration. Le StatefulSet généré doit être appliqué (et le broker redémarré de manière contrôlée), sans patch et sans effacer le PVC.
6. **Échec silencieux d'OpenSSL** : hostname Route trop long pour le `CN` X.509. Utiliser un `CN` court et le vrai hostname dans le SAN DNS ; le script actuel affiche les erreurs et protège les CA existantes.
7. **Dev Spaces / Skopeo** : configurer `XDG_RUNTIME_DIR`, `REGISTRY_AUTH_FILE` dans `$HOME` ; pas de chemins système `/run/containers`.
8. **Java Producer non compilé** : Dev Spaces ne résout pas `repo.maven.apache.org` ; utiliser ultérieurement un miroir Maven d'entreprise.

## 5. Déploiement neuf — scripts par fonction

**Attention : ne PAS lancer la séquence neuve dans le namespace où le POC existe déjà.** Elle bloque expressément en présence du StatefulSet `kafka-poc` ou de son PVC. Utiliser un **nouveau namespace autorisé** et revoir les manifests codant encore `midlleware` si le namespace diffère. Dans cette version, les scripts ciblent volontairement le namespace demandé `midlleware`.

Depuis la racine du dépôt :

```bash
bash bootstrap/00-preflight.sh           # droits, outils, gp3, absence de Kafka/PVC
bash bootstrap/10-images.sh             # import Skopeo : 4 Confluent + Kafbat
bash bootstrap/20-kafka.sh              # Cluster ID neuf, services, StatefulSet, PVC gp3
bash bootstrap/30-schema-registry.sh    # Registry + topic _schemas RF=1
bash bootstrap/40-connect.sh            # Worker distributed, topics internes RF=1
bash bootstrap/50-rest-proxy.sh         # REST Proxy HTTP interne
bash bootstrap/60-kafbat.sh             # Kafbat interne avec mot de passe dans Secret
bash bootstrap/90-tests.sh              # smoke tests Kafka/Registry/Connect/REST
```

Alternative : `bash bootstrap/install-all.sh` (étapes 00 à 60 uniquement, **pas** de Route ouverte automatiquement), puis `bash bootstrap/90-tests.sh`.

**Option seulement après validation du coeur :** `bash bootstrap/70-external-tls.sh` (Service, Route, CA locale mTLS, Secret, listener TLS), puis `TEST_EXTERNAL=1 bash bootstrap/90-tests.sh`. Le script externe est destiné à une **première installation**, pas au renouvellement de certificats.

Accès Kafbat depuis Dev Spaces : preview/port-forward local, ou Route HTTPS `kafka-ui/public/01-route.yaml` **après vérification du login**. Cette Route est intentionnellement non créée par l'installateur.

L'ancien `poc/02-cluster-id-secret.yaml` contient l'ID du POC historique, **NE PAS l'appliquer sur une nouvelle installation**. Le bootstrap crée son propre Secret et n'applique que les Services + le StatefulSet Kafka.

## 6. Tests / maintenance de l'instance actuelle

Sans repartir de zéro :

```bash
git pull --ff-only
bash bootstrap/90-tests.sh
TEST_EXTERNAL=1 bash bootstrap/90-tests.sh    # si les certificats locaux existent toujours
```

Les tests créent des topics/subjects dédiés (à nettoyer ultérieurement) mais ne suppriment jamais les données existantes. Le test TLS crée un Job client indépendant avec un Secret temporaire ; il ne copie plus de clés dans le broker.

Pour actualiser seulement le StatefulSet TLS en conservant le certificat existant et son hostname : `bash kafka-external/render.sh` ; ne pas relancer `prepare.sh` sans plan explicite de rotation TLS.

Pour retirer vite l'entrée externe Kafka : `oc delete route kafka-poc-external -n midlleware`. Pour retirer l'accès externe UI : `oc delete route kafka-ui -n midlleware`.

## 7. Limites et suite recommandée

- **Sécurité** : certificat CA local 30 jours sans rotation automatisée, listener interne PLAINTEXT, RBAC/ACL Kafka et SSO/RBAC UI à industrialiser. Les Routes publiques dépendent des contrôles réseau de l'entreprise.
- **Disponibilité** : 1 broker/controller, pas de quorum HA ; planifier une nouvelle architecture 3 controllers dédiés + 3 brokers, idéalement nouvelle instance plutôt que migration improvisée du PVC.
- **Stockage** : `gp3` (EBS CSI) existant, RWO lié à une AZ ; évaluer performance et reprise.
- **Métier** : installer de vrais plugins Kafka Connect et valider une Source/Sink ; Producer Java en pause en attendant Nexus/Artifactory ; ksqlDB optionnel.
- **Industrialisation** : remplacer ensuite les doubles manifests `poc/` et `kafka-external/` par des overlays Kustomize, CI GitLab, gestion PKI et secrets externes. Ce dépôt n'est **pas** une distribution de production validée.

## Sources techniques

- [Confluent : configuration des images Docker Kafka](https://docs.confluent.io/platform/current/installation/docker/config-reference.html)
- [Kafbat : authentification](https://ui.docs.kafbat.io/configuration/authentication)
- [OpenShift Routes (documentation Red Hat)](https://docs.redhat.com/en/documentation/openshift_container_platform/latest/html/ingress_and_load_balancing/routes)
