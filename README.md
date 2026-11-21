# Dark and Light — Dedicated Server (Docker + Wine)

🇬🇧 [English](#english) | 🇫🇷 [Français](#français)

---

## English

Docker container to host a **Dark and Light** dedicated server (SteamCMD App ID `630230`, anonymous download). There is no Linux build, so the Windows server (`DNLServer.exe`, Unreal Engine 4) runs under **Wine** (WineHQ stable 10.0, with `vcrun2013` and `vcrun2019` in the Wine prefix). The server is updated through SteamCMD each time the container starts.

- Docker Hub image: [`ludix0/dark_and_light`](https://hub.docker.com/r/ludix0/dark_and_light)
- GitHub sources: [`Ludix0/dark_and_light`](https://github.com/Ludix0/dark_and_light)
- Ports used: `7777/udp` (game), `7778/udp` (raw), `27015/udp` (Steam query)

### Clean shutdown

The Windows server ignores Docker's stop signal under Wine. On `docker compose stop`/`down`, the container therefore uses RCON internally: it sends `SaveWorld`, checks that the server answers `World Saved`, then sends `DoExit`. A normal stop takes about 15 seconds. If the game does not close by itself, it is killed after the save. RCON is always enabled **inside** the container for this purpose (password = `DNL_ServerAdminPassword`); its port is not published.

Each stop may leave a crash report in `Saved/Logs` (known game bug when closing under Wine). Reports older than `CRASH_REPORT_DAYS` days are deleted at each start. The `wine: Unhandled page fault` message shown at each start is harmless: the server keeps running.

### Requirements

- Docker and Docker Compose v2
- About 20 GB of free disk space, 8 GB+ of RAM
- UDP ports `7777`, `7778` and `27015` forwarded on your router/firewall

> ⏳ **The first start is long (20 to 40 min)**: server download, then Wine prefix setup. The container stays `health: starting` until the query port is open (map loaded).

### Method 1 — Quick install from Docker Hub (recommended)

```yaml
services:
  dark_and_light:
    image: ludix0/dark_and_light:latest
    container_name: dark_and_light
    restart: unless-stopped
    stop_grace_period: 90s
    volumes:
      - ./filesServer:/home/steam/dnl_server
      - ./saves:/home/steam/dnl_server/DNL/Saved
      - ./wineprefix:/home/steam/wineprefix
      - ./steamcmd:/home/steam/steamcmd
    environment:
      - TZ=Europe/Paris
      - PUID=1000
      - PGID=1000
      - UPDATE_ON_START=true
      - MAP=TheSacredPath
      - QUERY_PORT=27015
      - DNL_SessionName=My_DNL_Server
      - DNL_MaxPlayers=10
      - DNL_ServerPassword=CHANGEME
      - DNL_ServerAdminPassword=CHANGEMEADMIN
      - DNL_ServerPVE=True
    ports:
      - "7777:7777/udp"
      - "7778:7778/udp"
      - "27015:27015/udp"
```

Set `PUID`/`PGID` (output of `id -u` / `id -g`) and the passwords, then run `docker compose up -d`.

### Method 2 — Build from source (GitHub)

```bash
git clone https://github.com/Ludix0/dark_and_light.git
cd dark_and_light
cp .env.example .env   # then edit it
docker compose build
docker compose up -d
```

### Environment variables

| Variable | Required | Description |
|---|---|---|
| `PUID` / `PGID` | yes | Owner of the volumes on the host |
| `TZ` | no | Time zone |
| `UPDATE_ON_START` | no | `true` = SteamCMD update at each start |
| `SHUTDOWN_TIMEOUT` | no | Max seconds to wait for the game to close if the save is not confirmed (default 60; 15 s once the save is confirmed). Keep `stop_grace_period` above it |
| `CRASH_REPORT_DAYS` | no | Crash reports older than this many days are deleted at start (default 7) |
| `STEAM_USER` / `STEAM_PASSWORD` | no | Empty = anonymous login (enough for this server) |
| `MAP` | no | `TheSacredPath` (default), `TheShard`, or a full `/Game/...` path |
| `GAME_PORT` | no | Game port in the container (default 7777, raw port = +1) |
| `QUERY_PORT` | no | Steam query port (default 27015) |
| `RCON_PORT` | no | RCON TCP port inside the container (default 27020), used for the clean shutdown |
| `MULTIHOME` | no | Listen address (default `0.0.0.0`) |
| `EXTRA_URL_OPTIONS` | no | Extra `?Key=Value` options for the launch line |
| `EXTRA_ARGS` | no | Extra `-flag` arguments for the launch line |
| `DNL_<Key>` | no | Written as `<Key>=<value>` in `GameUserSettings.ini` `[ServerSettings]`. Empty = not written |

The provided `docker-compose.yml` lists every known setting. Settings marked "inherited from ARK" share the same engine but are not officially documented for Dark and Light: they are left empty, fill them in to try them.

> ⚠️ Community tip: use a session name **without spaces** and passwords of **5+ uppercase characters**.

### Volumes

| Volume | Content |
|---|---|
| `/home/steam/dnl_server` | Server files (SteamCMD) |
| `/home/steam/dnl_server/DNL/Saved` | Saves, `GameUserSettings.ini`, logs |
| `/home/steam/wineprefix` | Wine prefix (prepared once) |
| `/home/steam/steamcmd` | SteamCMD |

### Ports

| Port | Protocol | Usage |
|---|---|---|
| 7777 | UDP | Game |
| 7778 | UDP | Raw (game + 1) |
| 27015 | UDP | Steam query (server browser) |
| 27020 | TCP | RCON — internal only (not published), never expose it to the internet |

---

## Français

Conteneur Docker pour héberger un serveur dédié **Dark and Light** (SteamCMD App ID `630230`, téléchargement anonyme). Il n'existe pas de version Linux : le serveur Windows (`DNLServer.exe`, Unreal Engine 4) tourne sous **Wine** (WineHQ stable 10.0, avec `vcrun2013` et `vcrun2019` dans le préfixe Wine). Le serveur est mis à jour via SteamCMD à chaque démarrage du conteneur.

- Image Docker Hub : [`ludix0/dark_and_light`](https://hub.docker.com/r/ludix0/dark_and_light)
- Sources GitHub : [`Ludix0/dark_and_light`](https://github.com/Ludix0/dark_and_light)
- Ports utilisés : `7777/udp` (jeu), `7778/udp` (raw), `27015/udp` (requête Steam)

### Arrêt propre

Sous Wine, le serveur Windows ignore le signal d'arrêt de Docker. Lors d'un `docker compose stop`/`down`, le conteneur passe donc par RCON en interne : il envoie `SaveWorld`, vérifie que le serveur répond `World Saved`, puis envoie `DoExit`. Un arrêt normal prend environ 15 secondes. Si le jeu ne se ferme pas seul, il est coupé après la sauvegarde. RCON est donc toujours actif **à l'intérieur** du conteneur (mot de passe = `DNL_ServerAdminPassword`) ; son port n'est pas publié.

Chaque arrêt peut laisser un rapport de plantage dans `Saved/Logs` (défaut connu du jeu à la fermeture sous Wine). Les rapports de plus de `CRASH_REPORT_DAYS` jours sont supprimés à chaque démarrage. Le message `wine: Unhandled page fault` affiché à chaque démarrage est sans gravité : le serveur continue de fonctionner.

### Prérequis

- Docker et Docker Compose v2
- Environ 20 Go d'espace disque libre, 8 Go de RAM ou plus
- Ports UDP `7777`, `7778` et `27015` redirigés sur le routeur/pare-feu

> ⏳ **Le premier démarrage est long (20 à 40 min)** : téléchargement du serveur puis préparation du préfixe Wine. Le conteneur reste en `health: starting` tant que le port de requête n'est pas ouvert (carte chargée).

### Méthode 1 — Installation rapide depuis Docker Hub (recommandée)

Utiliser le `docker-compose.yml` de la section English ci-dessus, adapter `PUID`/`PGID` (résultat de `id -u` / `id -g`) et les mots de passe, puis lancer `docker compose up -d`.

### Méthode 2 — Construction depuis les sources (GitHub)

```bash
git clone https://github.com/Ludix0/dark_and_light.git
cd dark_and_light
cp .env.example .env   # puis le modifier
docker compose build
docker compose up -d
```

### Variables d'environnement

| Variable | Obligatoire | Description |
|---|---|---|
| `PUID` / `PGID` | oui | Propriétaire des volumes sur l'hôte |
| `TZ` | non | Fuseau horaire |
| `UPDATE_ON_START` | non | `true` = mise à jour SteamCMD à chaque démarrage |
| `SHUTDOWN_TIMEOUT` | non | Attente max (s) de la fermeture du jeu si la sauvegarde n'est pas confirmée (60 par défaut ; 15 s une fois la sauvegarde confirmée). Garder `stop_grace_period` au-dessus |
| `CRASH_REPORT_DAYS` | non | Les rapports de plantage plus vieux que ce nombre de jours sont supprimés au démarrage (7 par défaut) |
| `STEAM_USER` / `STEAM_PASSWORD` | non | Vide = connexion anonyme (suffisante ici) |
| `MAP` | non | `TheSacredPath` (défaut), `TheShard`, ou un chemin `/Game/...` complet |
| `GAME_PORT` | non | Port de jeu dans le conteneur (7777, port raw = +1) |
| `QUERY_PORT` | non | Port de requête Steam (27015) |
| `RCON_PORT` | non | Port RCON TCP dans le conteneur (27020), utilisé pour l'arrêt propre |
| `MULTIHOME` | non | Adresse d'écoute (`0.0.0.0`) |
| `EXTRA_URL_OPTIONS` | non | Options `?Clé=Valeur` supplémentaires au lancement |
| `EXTRA_ARGS` | non | Arguments `-option` supplémentaires au lancement |
| `DNL_<Clé>` | non | Écrit `<Clé>=<valeur>` dans `GameUserSettings.ini` `[ServerSettings]`. Vide = non écrit |

Le `docker-compose.yml` fourni liste tous les réglages connus. Ceux marqués « hérités d'ARK » viennent du même moteur mais ne sont pas documentés officiellement pour Dark and Light : ils sont laissés vides, à renseigner pour les essayer.

> ⚠️ Astuce de la communauté : nom de session **sans espace** et mots de passe de **5 caractères ou plus, en majuscules**.

### Volumes

| Volume | Contenu |
|---|---|
| `/home/steam/dnl_server` | Fichiers du serveur (SteamCMD) |
| `/home/steam/dnl_server/DNL/Saved` | Sauvegardes, `GameUserSettings.ini`, logs |
| `/home/steam/wineprefix` | Préfixe Wine (préparé une seule fois) |
| `/home/steam/steamcmd` | SteamCMD |

### Ports

| Port | Protocole | Usage |
|---|---|---|
| 7777 | UDP | Jeu |
| 7778 | UDP | Raw (jeu + 1) |
| 27015 | UDP | Requête Steam (navigateur de serveurs) |
| 27020 | TCP | RCON — interne uniquement (non publié), ne jamais l'exposer sur internet |
