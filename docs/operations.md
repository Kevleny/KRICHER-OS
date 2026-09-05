# Exploitation locale

## Adresses

- KRICHER OS : `http://127.0.0.1:3000`
- n8n : `http://127.0.0.1:5678`

Ces adresses ne sont accessibles que depuis l’OptiPlex.

## Sauvegardes

La tâche Windows `KRICHER OS - Sauvegarde quotidienne` s’exécute chaque jour à 03:30. Les sauvegardes quotidiennes sont conservées pendant 30 jours dans `K:\KRICHER-OS\Backups`, avec une archive mensuelle pendant 12 mois.

Chaque instantané contient :

- un export PostgreSQL au format personnalisé ;
- les données du volume n8n ;
- la configuration Docker, Caddy, les workflows et les scripts ;
- les secrets locaux nécessaires à une reprise complète.

Tous ces fichiers sont chiffrés en AES-256 avant leur écriture sur `K:`. La clé de récupération reste dans `.secrets/backup_recovery_key` et doit être conservée séparément du serveur pour couvrir une panne complète du disque système.

La tâche `KRICHER OS - Test de restauration` s’exécute le dimanche à 04:30. Elle contrôle les empreintes, déchiffre la dernière sauvegarde dans un dossier temporaire, inspecte l’export PostgreSQL et l’archive n8n, puis supprime les fichiers temporaires. Elle ne modifie jamais les données actives. Une restauration réelle reste protégée par le paramètre explicite `-ConfirmRestore` de `scripts/Restore-KricherOS.ps1`.

La page **Sécurité & sauvegardes** permet de lancer une sauvegarde et un test de restauration après confirmation.

## Notifications

Le gardien envoie une alerte urgente seulement lorsqu’un service reste indisponible après une tentative automatique de réparation. Une seconde notification annonce le retour à la normale. La tâche `KRICHER OS - Rapport hebdomadaire` envoie chaque dimanche à 18:00 un résumé des services, du stockage, des incidents et des sauvegardes.

Les notifications utilisent un compte SMTP. Les réglages sont conservés localement et le mot de passe est chiffré par Windows pour le compte qui exécute les tâches :

```powershell
.\scripts\Configure-MailNotifications.ps1
```

Le bouton **Envoyer un e-mail test** devient disponible dans le tableau de bord dès que cette configuration est terminée.

## Redémarrage et diagnostic

```powershell
docker compose up -d
docker compose ps
docker compose logs --tail 100
```

Les conteneurs redémarrent automatiquement avec Docker Desktop.

Les tâches Windows `KRICHER OS - Demarrage automatique` et `KRICHER OS - Supervision Windows` démarrent les services à l’ouverture de session et actualisent toutes les cinq minutes les mesures affichées dans le tableau de bord.

Toutes les tâches KRICHER OS passent par `wscript.exe` et `Run-PowerShellHidden.vbs`. PowerShell travaille ainsi sans ouvrir de fenêtre sur le Bureau.

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
