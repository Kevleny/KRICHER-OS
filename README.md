# KRICHER OS

Tableau de bord local du serveur personnel installé sur le Dell OptiPlex 3080.

## Services actuels

- KRICHER OS : tableau de bord et état des services, sur `http://127.0.0.1:3000`
- n8n : plateforme d’automatisation, sur `http://127.0.0.1:5678`
- PostgreSQL : base privée de n8n, accessible uniquement dans le réseau Docker interne
- n8n Task Runner : exécution isolée du code JavaScript et Python des workflows

Les deux interfaces écoutent uniquement sur la machine locale. Aucun accès distant n’est ouvert à ce stade.

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

La préparation des accès HTTPS à `www.kricher.fr` pour le tableau de bord et `n8n.kricher.fr` pour n8n se trouve dans [`docs/public-access.md`](docs/public-access.md). Cette configuration reste inactive tant que la zone DNS OVH et la redirection des ports de la box ne sont pas prêtes.
