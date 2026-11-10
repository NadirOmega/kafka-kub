# Kafbat UI — POC OpenShift

Image **officielle Alpine/non UBI** `kafbat/kafka-ui:a0aaba3` (exception temporaire à la politique d'images : nécessite accord de l'équipe sécurité). Ce dossier ne crée **aucune Route publique**, car l'authentification de l'UI n'est pas encore configurée.

## Importer l'image (Dev Spaces, si autorisé)

```bash
REG="image-registry.openshift-image-registry.svc:5000"
NS="midlleware"
TAG="a0aaba3"
export XDG_RUNTIME_DIR="$HOME/.local/run"
export XDG_CONFIG_HOME="$HOME/.config"
export REGISTRY_AUTH_FILE="$HOME/.config/containers/auth.json"
mkdir -p "$XDG_RUNTIME_DIR" "$(dirname "$REGISTRY_AUTH_FILE")"
chmod 700 "$XDG_RUNTIME_DIR"
skopeo login --authfile "$REGISTRY_AUTH_FILE" docker.io
oc whoami -t | skopeo login --authfile "$REGISTRY_AUTH_FILE" -u "$(oc whoami)" --password-stdin "$REG"
skopeo --insecure-policy copy --src-authfile "$REGISTRY_AUTH_FILE" --dest-authfile "$REGISTRY_AUTH_FILE" \
  "docker://docker.io/kafbat/kafka-ui:$TAG" "docker://$REG/$NS/kafbat-ui:$TAG"
oc get istag "kafbat-ui:$TAG" -n "$NS"
```

Le tag est explicitement fixé. Après import, relever le digest réel dans le registre de destination et le figer dans `02-deployment.yaml` pour un déploiement pérenne.

## Déployer et tester **sans exposition externe**

Depuis la racine du dépôt :

```bash
git pull --ff-only
oc apply -n midlleware -f kafka-ui/
oc rollout status deployment/kafka-ui -n midlleware --timeout=180s
oc port-forward -n midlleware svc/kafka-ui 18080:8080
```

Dans le navigateur du poste qui exécute réellement le port-forward : `http://localhost:18080`. Si Dev Spaces est distant, `localhost` sur le PC ne pointe **pas** vers Dev Spaces : employer uniquement le mécanisme de prévisualisation de ports homologué par la plateforme.

## Services intégrés

- Kafka : `kafka-poc-bootstrap:9092` (broker découvert via `advertised.listeners`)
- Schema Registry : `http://schema-registry:8081`
- Kafka Connect : `http://kafka-connect:8083`

## Exposition externe (étape séparée, NON activée)

Le droit de créer des Routes a été vérifié pour `midlleware`, mais la portée publique du routeur n'a pas été vérifiée. Avant toute Route HTTPS, configurer et tester l'authentification (SSO/OIDC ou proxy d'authentification), les droits et un contrôle d'accès réseau. Une Route sans `spec.host` peut obtenir un hostname attribué par OpenShift ; cela ne garantit pas l'accès Internet. Ne jamais publier l'interface anonyme qui peut administrer Kafka.

Documentation : https://ui.docs.kafbat.io/configuration/misc-configuration-properties
