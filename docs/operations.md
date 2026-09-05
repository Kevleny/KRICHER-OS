# Exploitation locale

## Adresses

- KRICHER OS : `http://127.0.0.1:3000`
- n8n : `http://127.0.0.1:5678`

Ces adresses ne sont accessibles que depuis l’OptiPlex.

## Sauvegardes

La tâche Windows `KRICHER OS - Sauvegarde quotidienne` s’exécute chaque jour à 03:30. Les sauvegardes sont conservées pendant 14 jours dans `K:\KRICHER-OS\Backups` sur le second disque NVMe.

Chaque instantané contient :

- un export PostgreSQL au format personnalisé ;
- les données du volume n8n ;
- la clé qui permet de déchiffrer les identifiants enregistrés dans n8n.
- les identifiants d’accès au tableau de bord public.

La clé de chiffrement et les identifiants sont sensibles. Le dossier de sauvegarde ne doit pas être partagé.

## Redémarrage et diagnostic

```powershell
docker compose up -d
docker compose ps
docker compose logs --tail 100
```

Les conteneurs redémarrent automatiquement avec Docker Desktop.

Les tâches Windows `KRICHER OS - Demarrage automatique` et `KRICHER OS - Supervision Windows` démarrent les services à l’ouverture de session et actualisent toutes les cinq minutes les mesures affichées dans le tableau de bord.

Le workflow n8n `KRICHER OS - Contrôle de santé` vérifie toutes les six heures le tableau de bord, n8n, PostgreSQL et la remontée des mesures Windows. Ses exécutions sont visibles dans n8n.

Après une modification du démarrage, `scripts/Register-RestartVerificationTask.ps1` programme un contrôle unique. Son résultat est écrit dans `.runtime/post-restart-report.json` après la prochaine ouverture de session.

## Stockage

Le second disque NVMe est monté sous `K:` avec l’étiquette `Sauvegarde`. Il reçoit les sauvegardes et exports de KRICHER OS. Les volumes actifs PostgreSQL et n8n restent dans le stockage Linux géré par Docker afin de préserver leurs permissions et leurs performances.

## Accès distant

Le domaine racine `kricher.fr` et les enregistrements de messagerie OVH restent inchangés. Le tableau de bord utilise `www.kricher.fr` avec une authentification séparée, et n8n utilise `n8n.kricher.fr`. Les deux accès publics passent par HTTPS.
