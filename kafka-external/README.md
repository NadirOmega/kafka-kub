# Kafka natif sur OpenShift — accès TLS passthrough (POC)

**État validé par les tests :** le broker KRaft écoute en interne sur `9092`, le listener `EXTERNAL:9094` a été activé, et un client Kafka avec certificats mTLS a produit et consommé via une Route OpenShift sur `443`. Ces tests ont été effectués depuis le réseau OpenShift ; l'accessibilité depuis un poste externe reste **à vérifier séparément**.

## Ressources versionnées

| Fichier | Utilisation |
| --- | --- |
| `01-service.yaml` | Service ClusterIP sur `9094` |
| `02-route.yaml` | Route OpenShift `passthrough` sans hostname en dur |
| `statefulset.template.yaml` | StatefulSet complet `INTERNAL`, `CONTROLLER`, `EXTERNAL` et mTLS, avec `EXTERNAL_HOST_PLACEHOLDER` |
| `prepare.sh` | Génération **initiale uniquement** des certificats (CA 30 jours), Secret et StatefulSet local |
| `render.sh` | Recrée seulement le YAML StatefulSet en réutilisant les certificats **existants** ; vérifie le SAN du hostname |
| `smoke-test.sh` | Test Kafka natif TLS Producer → Consumer dans un **Job isolé**, avec Secret client temporaire et nettoyage |
| `.gitignore` | Exclut le dossier `generated/` et les sauvegardes de certificats |

**Aucun hostname d'entreprise, certificat privé ou mot de passe ne doit être committé.**

## 1. Préparation initiale (déjà effectuée sur ce POC)

```bash
git pull --ff-only
# Une seule fois pour un nouveau jeu de certificats :
bash kafka-external/prepare.sh
```

`prepare.sh` génère localement `kafka-external/generated/` : `ca.crt`, `ca.key`, `server.p12`, `client.p12`, `client.properties`, `tls-secret.yaml`, `statefulset.yaml` et les fichiers de génération. **Il ne modifie pas le cluster.**

**Ne relance pas `prepare.sh` pour actualiser le hostname ou le StatefulSet si le TLS est déjà actif.** Le script refuse d'écraser le matériel existant ; un changement de CA/certificats nécessite une procédure de rotation explicite.

Pour reconstruire uniquement le YAML de déploiement avec le vrai hostname de la Route (qui reste local) :

```bash
bash kafka-external/render.sh
```

Ce script refuse de réutiliser le certificat si son SAN ne correspond plus au hostname courant.

## 2. Déploiement explicite (sans patch)

```bash
oc apply -n midlleware -f kafka-external/01-service.yaml -f kafka-external/02-route.yaml
oc apply -n midlleware -f kafka-external/generated/tls-secret.yaml
oc apply -n midlleware -f kafka-external/generated/statefulset.yaml
oc rollout status sts/kafka-poc -n midlleware --timeout=180s
```

**Sur notre POC actuel, ces ressources existent déjà : ne les réapplique pas sans changement réel.** Ne supprime jamais le PVC ni ne régénère le Cluster ID sur un cluster existant.

## 3. Test reproductible, sans copier de clé dans le broker

```bash
git pull --ff-only
bash kafka-external/smoke-test.sh
```

Le script récupère le hostname par `oc get route`, crée un Secret **temporaire** pour les certificats clients, puis un Job Kubernetes contenant un Kafka CLI. Il crée un topic éphémère au nom unique, publie puis consomme un message via le listener externe `:443`, affiche `NATIVE_KAFKA_443_OK` si le test est réussi, et **supprime le Job et son Secret** à la sortie.

**Le topic Kafka de test subsiste** (et peut être supprimé de manière contrôlée si voulu) ; le Job ne touche pas aux données existantes. Le test valide le chemin via la Route depuis le cluster, **pas** nécessairement depuis ton poste Windows ni depuis Internet.

Le script dépend des certificats présents dans `generated/`. Il n'utilise pas les copies manuelles de certificats éventuellement laissées dans `/tmp` du broker.

## 4. Nettoyer les anciens fichiers client du broker

Après un test réussi via le Job isolé, retirer les copies de test préalablement placées dans `/tmp` :

```bash
oc exec -n midlleware kafka-poc-0 -- sh -c 'rm -f /tmp/client.p12 /tmp/ca.crt /tmp/client.properties'
```

Cela ne supprime **pas** les certificats serveur montés depuis le Secret à `/etc/kafka/external-tls`.

## 5. Sécurité et retour arrière

- Le POC impose `EXTERNAL:SSL` avec **certificat client mTLS**. TLS ne remplace **pas** une politique d'autorisation Kafka (ACL) ni le contrôle réseau.
- Le listener `INTERNAL:9092` est encore en PLAINTEXT, réservé au réseau du cluster.
- Les certificats CA/autosignés sont valables **30 jours**, ne constituent pas une PKI entreprise et devront être renouvelés avec une procédure de rotation vérifiée.
- Pour supprimer immédiatement la voie d'entrée externe, exécuter `oc delete route kafka-poc-external -n midlleware`.
- Pour revenir au broker interne uniquement, utiliser le manifeste de référence `poc/03-statefulset.yaml` lors d'un redéploiement maîtrisé ; ne pas supprimer le PVC.
- Les secrets de test laissés dans des sauvegardes locales ou dans un shell doivent être protégés ou purgés après validation.

## Étape d'industrialisation suivante

Éliminer la duplication entre `poc/03-statefulset.yaml` et `statefulset.template.yaml` dans un futur overlay Kustomize/Helm, avec environnements séparés, gestion des secrets via une PKI d'entreprise et validation CI. Ne pas basculer le POC actif sur une nouvelle structure sans test de non-régression.
