# Kafbat UI — POC OpenShift, accès HTTPS protégé

Image officielle Kafbat UI `a0aaba3` (Alpine / non UBI ; exception POC à valider avec la SSI). Namespace `midlleware`.

## Composants

- `01-service.yaml` : Service interne `kafka-ui:8080`.
- `02-deployment.yaml` : UI Kafka, Schema Registry et Kafka Connect ; login `AUTH_TYPE=LOGIN_FORM` depuis le Secret `kafbat-ui-auth`.
- `public/01-route.yaml` : Route HTTPS OpenShift facultative, séparée pour **éviter une exposition accidentelle** lors de `oc apply -f kafka-ui/`.

## 1. Créer le Secret avant le déploiement

Depuis Dev Spaces, dans le bon projet OpenShift :

```bash
NS=midlleware
umask 077
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
printf '%s' 'admin' > "$TMP_DIR/username"
read -rsp 'Mot de passe Kafbat : ' UI_PASSWORD
printf '\n'
printf '%s' "$UI_PASSWORD" > "$TMP_DIR/password"
unset UI_PASSWORD
oc create secret generic kafbat-ui-auth -n "$NS" \
  --from-file=username="$TMP_DIR/username" \
  --from-file=password="$TMP_DIR/password" \
  --dry-run=client -o yaml | oc apply -n "$NS" -f -
rm -rf "$TMP_DIR"
trap - EXIT
```

**Ne pas versionner le mot de passe dans Git et ne pas partager la sortie des Secrets.** Cette authentification locale n'est pas un mécanisme SSO/RBAC complet. En cas d'exposition réellement Internet, faire approuver l'accès par la SSI et privilégier OIDC/SSO + restrictions réseau.

## 2. Mettre à jour l'UI existante et tester le login

```bash
git pull --ff-only
oc apply -n midlleware -f kafka-ui/
oc rollout status -n midlleware deployment/kafka-ui --timeout=180s
```

Avant la Route, accéder à l'UI par la prévisualisation de ports Dev Spaces déjà validée. Vérifier que le formulaire d'authentification est affiché, qu'une session anonyme ne donne pas accès à l'administration et qu'une connexion avec le compte fonctionne. Si ce contrôle échoue, **ne pas appliquer la Route**.

## 3. Activer explicitement la Route (après test du login)

```bash
oc apply -n midlleware -f kafka-ui/public/01-route.yaml
oc get route kafka-ui -n midlleware -o jsonpath='https://{.spec.host}{"\n"}'
```

OpenShift attribue normalement un hostname si `spec.host` est absent. Une Route admise ne prouve pas qu'elle est accessible depuis Internet : l'Ingress Controller peut être interne, et le réseau entreprise peut bloquer l'accès. Contrôler depuis un navigateur hors VPN/réseau entreprise si autorisé et inspecter `oc get route kafka-ui -n midlleware` en cas de problème.

La terminaison TLS est `edge` (navigateur → routeur en HTTPS ; routeur → Pod en HTTP interne). Le certificat par défaut du cluster doit être valide pour le domaine attribué.

## Désactivation de l'exposition

```bash
oc delete route kafka-ui -n midlleware
```

Ne pas désactiver l'authentification du Deployment lorsque la Route existe.

## Références

- https://ui.docs.kafbat.io/configuration/authentication/for-the-ui/basic-authentication
- https://docs.redhat.com/en/documentation/openshift_container_platform/4.21/html/ingress_and_load_balancing/routes
