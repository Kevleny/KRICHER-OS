# KRICHER OS

Tableau de bord local du serveur personnel installé sur le Dell OptiPlex 3080.

## Services actuels

- KRICHER OS : tableau de bord et état des services, sur `https://www.kricher.fr` avec authentification
- n8n : plateforme d’automatisation, sur `https://n8n.kricher.fr`
- PostgreSQL : base privée de n8n, accessible uniquement dans le réseau Docker interne
- n8n Task Runner : exécution isolée du code JavaScript et Python des workflows
- Surveillance Windows : contrôle et réparation automatiques des cinq services
- Assistant KRICHER OS : état du serveur et propositions de redémarrage avec confirmation

Les ports directs du tableau de bord et de n8n restent limités à la machine locale. Les accès publics passent uniquement par la passerelle HTTPS Caddy.

## Démarrage

La première installation génère deux secrets locaux avec `scripts/Initialize-Secrets.ps1`. Ils sont exclus de Git.

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Initialize-Secrets.ps1
docker compose up -d --build
```

## Contrôles utiles

```powershell
docker compose ps
docker compose logs --tail 100
docker compose exec postgres pg_isready -U n8n -d n8n
```

Les images sont épinglées à des versions précises. Une mise à jour doit être testée avant de modifier leurs versions.

Les sauvegardes quotidiennes sont écrites sur le second NVMe dans `K:\KRICHER-OS\Backups`. Les procédures courantes sont décrites dans [`docs/operations.md`](docs/operations.md).

Le chat fonctionne en mode local tant que `.secrets/openai_api_key` est vide. Ajouter une clé API OpenAI dans ce fichier active les réponses génératives au prochain redémarrage du tableau de bord. Le modèle peut seulement proposer une action prédéfinie ; Windows exécute uniquement les actions confirmées dans l’interface.

La configuration des accès HTTPS à `www.kricher.fr` pour le tableau de bord et `n8n.kricher.fr` pour n8n se trouve dans [`docs/public-access.md`](docs/public-access.md). Elle est active avec renouvellement automatique des certificats.
