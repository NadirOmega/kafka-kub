# Installation Kafka — 26 novembre 2026

Depuis la racine du dépôt, sélectionner le nouveau namespace (jamais midlleware). Le ServiceAccount default du namespace cible doit déjà avoir system:image-puller dans midlleware. Images existantes, aucun import Skopeo. Les YAML historiques sont adaptés à la volée sans modifier leurs sources ni leurs références d'images. Le digest Kafka historique doit rester disponible.

## Installation interne déjà effectuée
```bash
oc project NOM_DU_NAMESPACE
bash install-2026-11-26/install-external.sh
```

## Installation complète neuve
```bash
oc project NOM_DU_NAMESPACE
bash install-2026-11-26/install-all.sh
```

Prérequis: oc, openssl, keytool (Java), python3, sed, accès aux images, gp3 et droits sur ressources, Routes, Secrets, Jobs. Le script complet refuse un cluster existant. Le complément externe refuse un listener TLS ou Secret TLS existant et utilise le StatefulSet complet historique (POC mono-broker). Ne pas l'utiliser pour une rotation ou sur un StatefulSet personnalisé sans revue.

Certificats dans generated/<namespace>/<date_heure>/ (ignoré par Git, permissions privées). Validité 30 jours par défaut, CERT_DAYS configurable. Conserver les clés privées côté espace sécurisé. Python: ca.crt, client.crt, client.key. MuleSoft/Java: client-keystore.jks, truststore.jks et mots de passe dans passwords.txt (client key password identique au client keystore password). Endpoint dans endpoint.txt. SSL/mTLS, pas HTTPS pour Kafka. Les JKS serveur sont exportés pour compatibilité mais le broker utilise PKCS12/PEM. Vérifier la Route et le login Kafbat depuis le réseau cible. Le smoke test crée un topic et le conserve. Si une étape échoue, inspecter les objets et les fichiers avant toute reprise; aucune suppression automatique des ressources persistantes. Ne jamais partager les secrets ou la CA privée. Installation non exécutée sur un cluster vierge lors de la rédaction.
