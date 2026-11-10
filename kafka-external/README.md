# Kafka natif via OpenShift Route TLS passthrough (POC)

Le **même broker** `kafka-poc-0` sert les clients internes en PLAINTEXT sur 9092 et les clients externes en Kafka natif TLS sur 443 (port du Pod : 9094). Kafka Connect, REST Proxy, Schema Registry et Kafbat restent sur 9092, sans changement.

**Hostname réellement attribué par la Route :**

`kafka-poc-external-midlleware.apps.dev-app-hub.0k6e.p1.openshiftapps.com`

Il figure **explicitement** dans `03-statefulset-tls.yaml`, sous `KAFKA_ADVERTISED_LISTENERS`, avec le port **443**. Ce hostname est aussi utilisé comme SAN du certificat créé par le script. S'il change, il faut régénérer les certificats et modifier le manifeste Git avant déploiement.

## Prérequis

- Route `kafka-poc-external` et Service `kafka-poc-external` créés ; le listener du broker n'est pas encore activé.
- `openssl`, `keytool`, `oc` disponibles dans Dev Spaces.
- Accès `oc create secret` dans `midlleware`.
- Acceptation de l'exposition du Kafka POC via mTLS ; ce n'est pas une configuration de production (pas d'ACL par identité).
- Un arrêt bref du broker mono-nœud est attendu pendant le rollout. **Ne supprimer ni le PVC ni le Secret CLUSTER_ID.**

## Déploiement ordonné

Depuis la racine du dépôt Git :

```bash
git pull --ff-only

# Crée une CA de POC, un certificat broker (SAN = hostname de la Route),
# un certificat client et le Secret serveur Kubernetes.
bash kafka-external/create-tls-secret.sh

# Met à jour le MÊME StatefulSet Kafka avec trois listeners.
oc apply -n midlleware -f kafka-external/03-statefulset-tls.yaml
oc rollout status -n midlleware statefulset/kafka-poc --timeout=180s
```

Le script écrit les certificats clients et la CA dans `$HOME/kafka-external-tls` (permissions privées) ; **ne jamais pousser `client.key`, `ca.key` ou le mot de passe du magasin dans Git**. La CA générée localement est nécessaire aux clients externes et les certificats durent 30 jours. Le script refuse de remplacer un Secret ou des fichiers préexistants afin d'éviter des rotations accidentelles.

## Test du handshake externe depuis un poste autorisé

```bash
HOST=kafka-poc-external-midlleware.apps.dev-app-hub.0k6e.p1.openshiftapps.com
openssl s_client -connect "$HOST:443" -servername "$HOST" \
  -CAfile "$HOME/kafka-external-tls/ca.crt" \
  -cert "$HOME/kafka-external-tls/client.crt" \
  -key "$HOME/kafka-external-tls/client.key" \
  -verify_return_error </dev/null 2>&1 | grep -E 'Verify return code|Verification:'
```

Ce test confirme TLS/mTLS, **pas** la production Kafka. Pour valider le protocole Kafka, utiliser `kcat` ou `kafka-console-producer` avec le certificat client et les paramètres SSL appropriés.

## Important

- `Route TLS passthrough` = **Kafka TCP chiffré**, sans HTTP.
- Le port client visible de l'extérieur est **443** ; ne pas annoncer 9094 aux clients.
- Le certificat doit être validé par les clients via notre CA de POC. Il n'utilise pas le certificat wildcard du routeur.
- Pas de second cluster, pas de changement de PVC / `cluster.id` / `node.id`.
- Le StatefulSet standard `poc/03-statefulset.yaml` reste la variante **interne uniquement**. Ne pas la réappliquer après activation de TLS sans intention de retour arrière : Kubernetes enlèverait le listener externe.

Sources : https://docs.confluent.io/platform/current/kafka/listeners.html ; https://docs.confluent.io/platform/8.4/security/authentication/mutual-tls/overview.html ; https://docs.redhat.com/en/documentation/openshift_container_platform/4.19/html/ingress_and_load_balancing/routes
