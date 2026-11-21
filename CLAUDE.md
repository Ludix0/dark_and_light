# Dark and Light — serveur dédié Docker + Wine

Serveur dédié Dark and Light (SteamCMD 630230) en conteneur. Le serveur est Windows uniquement : il tourne sous Wine 10.0 avec un écran virtuel Xvfb. En service sur le réseau jeux (192.168.3.0/24) de Ludo.

**Pièges du jeu (arrêt, RCON, plantages, chronologie du démarrage) : voir `notes-techniques.md`.** À lire avant de toucher à `start_server.sh`.

## Structure des fichiers

| Fichier | Rôle |
|---|---|
| `Dockerfile` | Image `cm2network/steamcmd` épinglée par digest + WineHQ 10.0 + winetricks (`vcrun2013`, `vcrun2019`) |
| `docker-compose.yml` | Service `dark_and_light`, volumes, ports, tous les réglages `DNL_*` commentés. `stop_grace_period: 90s` |
| `start_server.sh` | PID 1 (via tini) : PUID/PGID, Xvfb, mise à jour SteamCMD, préfixe Wine, écriture de `GameUserSettings.ini`, nettoyage des rapports de plantage, lancement, arrêt propre par RCON |
| `healthcheck.sh` | Sain quand le port de requête UDP est ouvert (`/proc/net/udp`) |
| `.env` | **Lien symbolique** vers `~/volumes/secrets/steam-account.env`, partagé par tous les serveurs de jeu. Ne jamais l'afficher ni le publier |
| `.env.example` | Modèle publié des variables (`jeux1`, `steamQuery`, `rcon`, `maxPlayers`, `password`, `adminPassword`) |
| `README.md` | Doc publique EN + FR (GitHub et page Docker Hub) |
| `description.txt` | Description courte Docker Hub (anglais, ≤ 100 car.), non commitée |
| `notes-techniques.md` | Copie de `~/.claude/notes-serveur-jeux/dark-and-light.md` (la source fait foi) |
| `annexes/` | Outils de diagnostic, non publiés : `rcon_test.py` (RCON depuis l'hôte), `rcon_bash_test.sh` (client bash dans le conteneur), `dockerhub_update.py` (textes Docker Hub) |

Volumes sur l'hôte : `~/volumes/dark_and_light/{filesServer,saves,wineprefix}` et `~/volumes/steamcmd` (partagé).

## Fonctionnement de l'arrêt (résumé)

`docker compose stop` → SIGTERM → `shutdown_server` : RCON `SaveWorld` (vérifie `World Saved`, sinon un nouvel essai), puis `DoExit`. Attente max 15 s si la sauvegarde est confirmée, `SHUTDOWN_TIMEOUT` (60 s) sinon, puis `pkill` en tant que `steam`. RCON est forcé à `True` par le script (la variable `DNL_RCONEnabled` est ignorée) et son port n'est pas publié.

Les rapports de plantage (`*.crashstack`, `crashcallstack-*.txt`, `*.dmp` dans `Saved/Logs`) de plus de `CRASH_REPORT_DAYS` jours (7) sont supprimés à chaque démarrage.

## Tester

- RCON depuis l'hôte : `RCON_PASS=$(docker exec dark_and_light printenv DNL_ServerAdminPassword) python3 annexes/rcon_test.py <IP du conteneur> 27116 ListPlayers`
- Arrêt propre : attendre **au moins 2 min** après le lancement du jeu (sinon faux échec, voir `notes-techniques.md`), puis `docker compose stop` et lire `docker logs dark_and_light | grep start_server`. Attendu : `World Saved`, `Exiting...`, arrêt en ~12 s sans « arrêt forcé ».
- Un redémarrage prend 2 à 15 min (vérification SteamCMD selon la charge disque, puis ~85 s de chargement).

## Publication

- GitHub : `Ludix0/dark_and_light` (branche `main`), identifiant enregistré dans `git credential`.
- Docker Hub : `ludix0/dark_and_light:latest`. `docker push` fonctionne directement (Docker connecté). Les textes Docker Hub (description + README) demandent un jeton Docker Hub fourni par Ludo : `DOCKERHUB_TOKEN=... python3 -I annexes/dockerhub_update.py ludix0 dark_and_light`.
- Workflow complet : skill `publish-docker-project`.
