# Dark and Light — valeurs de référence (SteamID: 630230)

À utiliser avec le skill `server_game_docker` pour la structure générale (Dockerfile, docker-compose.yml, start_server.sh, README, workflow, pièges courants).

Validé le 2026-11-21 : serveur joignable par les joueurs, sauvegarde et arrêt propre via RCON testés (projet `~/projets/dark_and_light/`, image `ludix0/dark_and_light`, dépôt GitHub `Ludix0/dark_and_light`).

## Téléchargement
Connexion SteamCMD **anonyme** suffisante (`+@sSteamCmdForcePlatformType windows +app_update 630230 validate`). Environ 3,8 Go. La vérification `validate` à chaque démarrage prend 1 à 10 min selon la charge disque.

## Binaire serveur (Windows uniquement → Wine, Unreal Engine 4 dérivé d'ARK)
`DNL/Binaries/Win64/DNLServer.exe`, lancé depuis ce dossier avec :
```
wine DNLServer.exe "<carte>?listen?Port=7777?QueryPort=27015?RCONEnabled=True?RCONPort=<port>" -server -game -log -nosteamclient
```
Cartes : `TheSacredPath` = `/Game/DNL/Maps/CapeOfSacredPath/DNL_ALL` (défaut), `TheShard`.

## Ports officiels
- `7777/udp` jeu, `7778/udp` raw (toujours jeu + 1, non configurable), `27015/udp` requête Steam.
- Garder le **même numéro** côté hôte et conteneur pour que le serveur s'annonce correctement à Steam.
- RCON TCP : actif en interne uniquement, jamais publié.

## Dépendances spécifiques
- WineHQ stable `10.0`, winetricks amont épinglé : `vcrun2013`, `vcrun2019`.
- `xvfb` (écran virtuel requis par Wine et UE4), `gosu`, `tini`, `procps`.

## Configuration
- Réglages dans `Saved/Config/WindowsServer/GameUserSettings.ini`, section `[ServerSettings]`, réécrits à chaque démarrage depuis les variables `DNL_<Clé>` (vide = non écrit).
- Conseils communauté : nom de session **sans espace**, mots de passe de **5+ caractères en majuscules**.
- Sauvegarde du monde : `Saved/SavedDnL/DNL_ALL.dnl` (~15 Mo).

## Arrêt propre (piège important)
- `DNLServer.exe` **ignore SIGTERM et SIGINT** sous Wine : relayer le signal (méthode Space Engineers) ne fait rien, le jeu est tué sans sauvegarde.
- Solution : passer par **RCON** (protocole Source, mot de passe = `ServerAdminPassword`), forcé à `True` par le script : `SaveWorld` → réponse `World Saved`, puis `DoExit` → réponse `Exiting...`. Arrêt complet en ~12 s.
- Le serveur **ignore une commande RCON reçue avant la réponse à l'authentification** : envoyer le paquet d'auth, lire la réponse (14 octets), puis seulement envoyer la commande.
- Client RCON possible en bash pur via `/dev/tcp` (pas de dépendance), voir `start_server.sh` du projet.
- `DoExit` peut faire planter le jeu à la fermeture (rapport « Fatal error », `*.crashstack` + `Dump*.dmp` dans `Saved/Logs`) et le processus reste bloqué : une fois `World Saved` confirmé, attendre 15 s max puis tuer (`pkill` **en tant que steam**, `cap_drop: ALL`). Nettoyer les vieux rapports au démarrage.

## Démarrage (chronologie observée)
- Lancement du .exe → port RCON ouvert ~55 s → jeu réellement prêt ~85 s.
- **Ne pas envoyer `SaveWorld` entre l'ouverture du port RCON et la fin du chargement** : le jeu plante (aucune sauvegarde). Pour tester l'arrêt, attendre au moins 2 min après le lancement.
- `wine: Unhandled page fault on read access to 00000000000000E3 ... starting debugger...` après `NetWork::Startup` : apparaît **à presque chaque démarrage**, sans conséquence (le serveur continue et répond). Ne pas s'en servir comme repère de fin de démarrage : il n'apparaît pas toujours.
- Premier démarrage : 20 à 40 min (téléchargement + préfixe Wine).

## Healthcheck
Socket UDP du port de requête ouverte dans `/proc/net/udp` (= carte chargée). L'image n'a ni `ss` ni `netstat`.
