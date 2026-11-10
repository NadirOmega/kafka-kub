# Kafka externe natif : Route OpenShift TLS passthrough (POC)

**Aucun hostname de cluster, certificat, clé privée ni mot de passe n'est enregistré dans Git.**

Le listener interne Kafka `9092` (Kafka Connect, Schema Registry, REST Proxy, Kafbat) et le controller `9093` restent identiques. Le même Pod Kafka écoute également sur `EXTERNAL:9094` en **SSL + authentification mutuelle TLS obligatoire (mTLS)**. La Route OpenShift utilise le port extérieur `443`, le protocole Kafka natif (ni HTTP ni REST), et le **SNI** pour sélectionner le backend.

Ce dispositif est **un POC à certificat CA local de 30 jours, non homologué production**. Pour la production : CA entreprise, gestion du cycle de vie, ACL Kafka, rotation certs, NetworkPolicies et autorisation de la Route. Le certificat de test doit être explicitement approuvé par le client externe.

## Fichiers dans le dépôt

- `01-service.yaml` : Service dédié `kafka-poc-external:9094`
- `02-route.yaml` : Route `passthrough` sans `spec.host` (hostname généré par OpenShift)
- `statefulset.template.yaml` : **StatefulSet complet**, avec `EXTERNAL_HOST_PLACEHOLDER` (NE PAS appliquer directement)
- `prepare.sh` : récupère le vrai hostname depuis la Route, génère les certificats mTLS et le StatefulSet complet **localement**
- `.gitignore` : ignore `generated/` (contient notamment les clés privées et l'URL réelle)

Le fichier `poc/03-statefulset.yaml` reste **inchangé**, comme référence de retour à la configuration interne initiale.

## 1. Préparation locale (Dev Spaces)

Le Service et la Route que tu as déjà créés peuvent rester en place : le Pod actuel **n'écoute pas encore sur 9094**.

Depuis la racine de `kafka-kub` :

```bash
git pull --ff-only
bash kafka-external/prepare.sh
```

Le script nécessite `oc`, `openssl` et `sed`. Il n'exécute **aucun `oc apply`**, pour ne pas redémarrer Kafka sans contrôle.

Il crée sous `kafka-external/generated/` :
- `tls-secret.yaml` : Secret Kubernetes avec `server.p12`, CA de confiance et mot de passe PKCS12
- `statefulset.yaml` : remplacement de `EXTERNAL_HOST_PLACEHOLDER` avec le hostname réel fourni par `oc get route`
- `ca.crt`, `client.p12`, `client.properties` : matériel d'authentification côté client pour les tests
- les clés privées et autres fichiers de création de certificats ; **ne jamais partager ni pousser ce dossier sur Git**

Ce sont des secrets de test. Leur utilisation doit rester dans un environnement autorisé.

## 2. Déployer (après vérification des fichiers locaux)

```bash
oc apply -n midlleware -f kafka-external/generated/tls-secret.yaml
oc apply -n midlleware -f kafka-external/generated/statefulset.yaml
oc rollout status statefulset/kafka-poc -n midlleware --timeout=180s
```

Ne jamais supprimer le PVC existant ni régénérer son Cluster ID.

## 3. Vérifier Kafka interne après redémarrage

```bash
oc exec -n midlleware kafka-poc-0 -- kafka-topics \
  --bootstrap-server kafka-poc-bootstrap:9092 --list
```

## 4. Vérifier le certificat externe et le protocole Kafka

Sur une machine **autorisée à joindre la Route** et disposant des certificats clients transférés de manière sécurisée :

```bash
HOST="$(oc get route kafka-poc-external -n midlleware -o jsonpath='{.spec.host}')"
openssl s_client -connect "$HOST:443" -servername "$HOST" \
  -CAfile kafka-external/generated/ca.crt -verify_return_error </dev/null
```

**Note :** ce premier contrôle TLS sans certificat client peut se terminer avec une alerte client-certificate-required (c'est attendu avec mTLS). Ce qui compte aussi est la chaîne serveur et le SAN du hostname.

Le client Kafka natif doit être configuré avec :
```properties
bootstrap.servers=HOST_RECU_DEPUIS_OPENSHIFT:443
security.protocol=SSL
ssl.truststore.type=PEM
ssl.truststore.location=/chemin/ca.crt
ssl.keystore.type=PKCS12
ssl.keystore.location=/chemin/client.p12
ssl.keystore.password=MOT_DE_PASSE_CLIENT_LOCAL
```

Les valeurs complètes, **locales et non versionnées**, sont dans `kafka-external/generated/client.properties`.

Un client Kafka `kcat` ou `kafka-broker-api-versions` disposant de TLS doit pouvoir récupérer les métadonnées ; vérifier qu'elles annoncent **l'hôte extérieur et le port 443**. Le routage TLS SNI doit être conservé : utiliser le hostname, pas une IP seule.

**Attention :** les logiciels clients n'utilisent pas tous le même format de magasin de clés ; `client.properties` est prévu pour les outils Java Kafka.

## Nettoyage / retour arrière

Pour retirer **immédiatement** l'accès extérieur :

```bash
oc delete route kafka-poc-external -n midlleware
```

Le broker reste opérationnel en interne. Le changement de StatefulSet initial peut être annulé séparément en réappliquant `poc/03-statefulset.yaml`, avec un nouveau redémarrage contrôlé. Ne pas supprimer le PVC.

## Références

- https://docs.confluent.io/platform/current/installation/docker/config-reference.html
- https://docs.confluent.io/platform/current/kafka/listeners.html
- https://kafka.apache.org/43/security/encryption-and-authentication-using-ssl/
