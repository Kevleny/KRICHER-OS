# Accès public à KRICHER OS et n8n

Le tableau de bord utilise `www.kricher.fr` et n8n utilise `n8n.kricher.fr`. Le domaine racine `kricher.fr` et les enregistrements de messagerie restent inchangés.

L’accès public est actif. Les deux noms DNS pointent vers la box, les ports TCP 80 et 443 sont redirigés vers l’OptiPlex et le pare-feu Windows autorise ces deux ports. Caddy a obtenu les certificats HTTPS et les renouvelle automatiquement.

## Préparation réseau

1. Réserver l’adresse locale `192.168.1.74` pour l’OptiPlex dans la box.
2. Dans la zone DNS OVH de `kricher.fr`, remplacer l’enregistrement `A` de `www` et créer un enregistrement `A` pour `n8n`, tous deux vers l’adresse IPv4 publique de la box.
3. Si cette adresse publique change, configurer OVH DynHost pour `www.kricher.fr` et `n8n.kricher.fr`.
4. Rediriger les ports TCP `80` et `443` de la box vers `192.168.1.74`.
5. Exécuter `scripts/Enable-PublicFirewall.ps1` en administrateur pour autoriser uniquement les ports TCP `80` et `443` dans le pare-feu Windows.

Ne pas créer d’enregistrement `AAAA` tant qu’IPv6 et son pare-feu n’ont pas été configurés et testés.

## Activation

Vérifier d’abord que `n8n.kricher.fr` résout vers l’adresse publique de la box. Activer ensuite la passerelle HTTPS :

```powershell
docker compose -f compose.yaml -f compose.public.yaml up -d
docker compose -f compose.yaml -f compose.public.yaml ps
docker compose -f compose.yaml -f compose.public.yaml logs gateway --tail 100
```

Caddy obtient et renouvelle automatiquement les certificats HTTPS. Les volumes `caddy_data` et `caddy_config` conservent les certificats et leur état.

## Contrôles

- ouvrir `https://n8n.kricher.fr` depuis un téléphone en données mobiles ;
- ouvrir `https://www.kricher.fr` et vérifier l’authentification du tableau de bord ;
- vérifier que HTTP redirige vers HTTPS ;
- vérifier la connexion n8n et l’exécution d’un workflow de test ;
- activer l’authentification à deux facteurs du compte propriétaire n8n ;
- vérifier un webhook avec son URL publique.

Les identifiants du tableau de bord sont conservés localement dans `.secrets/dashboard_credentials.txt` et inclus dans la sauvegarde protégée sur `K:`.
