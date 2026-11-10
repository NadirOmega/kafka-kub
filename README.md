# Kafka OpenShift — POC Confluent Kafka KRaft sans Operator

**Documentation à jour :**
- [HANDOFF.md](HANDOFF.md) — contexte technique, architecture validée, incidents et limitations
- [bootstrap/README.md](bootstrap/README.md) — installation **de zéro**, scripts par composant et tests
- [kafka-external/README.md](kafka-external/README.md) — listener Kafka TLS/mTLS sur Route passthrough :443

## Plateforme fonctionnelle observée (10 novembre 2026)

Namespace **`midlleware`**. Kafka KRaft mono-broker avec volume `gp3` et listeners `INTERNAL:9092`, `CONTROLLER:9093`, `EXTERNAL:9094` (Route TLS passthrough sur :443). Schema Registry, Kafka Connect, REST Proxy et Kafbat UI sont opérationnels. Producer/consumer Kafka natif sur :443 testés **depuis un Pod**, non depuis un PC externe.

Confluent `cp-*:8.4.0-1-ubi9`. Kafbat `a0aaba3` officielle **non UBI** — dérogation POC. UI via Route HTTPS avec `LOGIN_FORM` (Secret Kubernetes).

## Nouveau déploiement (namespace vide uniquement)

```bash
oc project midlleware
bash bootstrap/00-preflight.sh
bash bootstrap/install-all.sh
bash bootstrap/90-tests.sh
```

`install-all.sh` réalise images → Kafka → Schema Registry → Connect → REST Proxy → Kafbat. Il refuse le StatefulSet ou le PVC Kafka existant. Il **ne crée aucune Route publique**.

Les extensions sont **optionnelles** :

```bash
bash bootstrap/65-kafbat-route.sh   # UI HTTPS avec login (si autorisé)
bash bootstrap/70-external-tls.sh   # Kafka natif mTLS via Route 443
TEST_EXTERNAL=1 bash bootstrap/90-tests.sh
```

**Ne lance pas l'installation neuve sur le POC actuellement déployé** : le but est de reconstruire un environnement vide, pas de réinitialiser ses données. Pour tester l'instance actuelle, utilise uniquement :

```bash
bash bootstrap/90-tests.sh
```

## Avertissements

- `poc/02-cluster-id-secret.yaml` est un ancien Secret propre au PVC historique. **Ne jamais appliquer tout `poc/` sur une nouvelle installation** : `bootstrap/20-kafka.sh` génère son propre ID stable.
- `poc/03-statefulset.yaml` décrit le broker **interne seulement**. `kafka-external/statefulset.template.yaml` sert de modèle pour la version TLS ; le hostname réel est injecté localement, jamais dans Git.
- Les répertoires `bootstrap/generated/` et `kafka-external/generated/` contiennent des configurations et secrets locaux, ignorés par Git.
- Les certificats de test sont valables 30 jours. Leur rotation n'est pas automatisée.
- POC mono-broker avec listener interne PLAINTEXT. **Non homologué production**.

Voir [bootstrap/README.md](bootstrap/README.md) avant toute exécution.
