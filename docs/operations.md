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

La tâche `KRICHER OS - Surveillance et controle` s’exécute toutes les deux minutes. Elle surveille le tableau de bord, Caddy, n8n, son moteur d’exécution et PostgreSQL. Après deux échecs consécutifs, elle tente de redémarrer uniquement le service concerné. Si un service critique reste indisponible pendant quatre contrôles, elle peut redémarrer Windows. Deux garde-fous empêchent les boucles : six heures entre deux redémarrages et deux redémarrages maximum sur vingt-quatre heures.

La page **Infrastructure** expose les mêmes actions manuelles avec une confirmation. Le serveur n’accepte que le redémarrage d’un service connu, de toute la pile ou de Windows. L’assistant ne reçoit aucun accès à PowerShell et ne peut que préparer l’une de ces actions.

Le workflow n8n `KRICHER OS - Contrôle de santé` vérifie toutes les cinq minutes les cinq services et la remontée des mesures Windows. Ses exécutions sont visibles dans n8n. La réparation reste assurée par Windows afin de continuer à fonctionner lorsque n8n est lui-même arrêté.

## Assistant

Le chat de la page **Assistant** répond localement aux demandes d’état et de redémarrage courantes. Une clé API OpenAI placée seule dans `.secrets/openai_api_key` active les réponses génératives après un redémarrage du tableau de bord :

```powershell
docker compose -f compose.yaml -f compose.public.yaml up -d --force-recreate dashboard
```

La clé reste exclue de Git. Elle n’est jamais envoyée au navigateur ni inscrite dans les journaux.

Après une modification du démarrage, `scripts/Register-RestartVerificationTask.ps1` programme un contrôle unique. Son résultat est écrit dans `.runtime/post-restart-report.json` après la prochaine ouverture de session.

## Stockage

Le second disque NVMe est monté sous `K:` avec l’étiquette `Sauvegarde`. Il reçoit les sauvegardes et exports de KRICHER OS. Les volumes actifs PostgreSQL et n8n restent dans le stockage Linux géré par Docker afin de préserver leurs permissions et leurs performances.

## Accès distant

Le domaine racine `kricher.fr` et les enregistrements de messagerie OVH restent inchangés. Le tableau de bord utilise `www.kricher.fr` avec une authentification séparée, et n8n utilise `n8n.kricher.fr`. Les deux accès publics passent par HTTPS.
