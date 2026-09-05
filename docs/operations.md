# Exploitation locale

## Adresses

- KRICHER OS : `http://127.0.0.1:3000`
- n8n : `http://127.0.0.1:5678`

Ces adresses ne sont accessibles que depuis l’OptiPlex.

## Sauvegardes

La tâche Windows `KRICHER OS - Sauvegarde quotidienne` s’exécute chaque jour à 03:30. Les sauvegardes sont conservées pendant 14 jours dans `Documents\KRICHER-OS-Backups`.

Chaque instantané contient :

- un export PostgreSQL au format personnalisé ;
- les données du volume n8n ;
- la clé qui permet de déchiffrer les identifiants enregistrés dans n8n.

La clé de chiffrement est sensible. Le dossier de sauvegarde ne doit pas être partagé.

## Redémarrage et diagnostic

```powershell
docker compose up -d
docker compose ps
docker compose logs --tail 100
```

Les conteneurs redémarrent automatiquement avec Docker Desktop.

## Stockage

Le second disque NVMe est détecté mais ne possède pas de lettre de lecteur. Il n’a pas été formaté ni modifié afin de préserver d’éventuelles données existantes.
