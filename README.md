# Kafka OpenShift (sans Operator)

POC Kafka KRaft dans le namespace `midlleware`.

Les manifests Kubernetes sont versionnés sous `poc/`. Les images sont issues du registre OpenShift interne.

> Déploiement POC : 1 broker/controller combiné, PLAINTEXT interne uniquement. Non homologué production.

Appliquer les ressources : `oc apply -n midlleware -f poc/`.

Avant le premier démarrage, vérifier que le `CLUSTER_ID` du Secret correspond à celui des éventuels volumes déjà initialisés. Ne jamais changer ce Secret pour un cluster existant.
