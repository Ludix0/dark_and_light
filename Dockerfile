# Dark and Light - Dedicated Server (Steam App: 630230)
# Pas de binaire Linux natif : DNLServer.exe (Unreal Engine 4, base ARK)
# tourne sous Wine + Xvfb.
#
# Build :   docker compose build
# Lancer :  docker compose up -d
#
# Base : cm2network/steamcmd:root (Debian 13 trixie), épinglée par digest SHA256
# (même digest que le projet space-engineers, déjà validé avec Wine).
# Pour mettre à jour la base : docker pull cm2network/steamcmd:root puis
#   docker inspect --format='{{index .RepoDigests 0}}' cm2network/steamcmd:root
FROM cm2network/steamcmd@sha256:e6b6b3503bf0e41feafe12dc709c90151afba193e1292cac55d28a7d470b1493

# Version WineHQ épinglée (dépôt officiel WineHQ).
ARG WINE_VERSION=10.0.0.0~trixie-1

# Note : lib32gcc-s1 / lib32stdc++6 (SteamCMD 32 bits) sont déjà dans l'image de base.
#   gosu      : abandon des droits root vers l'utilisateur steam (PUID/PGID)
#   tini      : PID 1 minimal (relais des signaux, ramassage des zombies)
#   xvfb/xauth: écran virtuel exigé par Wine et par les installeurs winetricks
#   winbind   : NTLM, utilisé par certains composants Windows sous Wine
#   cabextract/unzip : requis par winetricks pour extraire les installeurs Microsoft
#   procps    : pgrep/pkill pour l'arrêt propre du serveur
RUN dpkg --add-architecture i386 \
    && apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates wget gnupg \
    && mkdir -pm755 /etc/apt/keyrings \
    && wget -qO /etc/apt/keyrings/winehq-archive.key https://dl.winehq.org/wine-builds/winehq.key \
    && wget -qNP /etc/apt/sources.list.d/ https://dl.winehq.org/wine-builds/debian/dists/trixie/winehq-trixie.sources \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        gosu tini procps \
        xvfb xauth winbind cabextract unzip \
    # --no-install-recommends : évite des centaines de Mo de paquets inutiles
    # sur un serveur sans écran (pilotes graphiques, codecs, GTK, sane…).
    && apt-get install -y --no-install-recommends \
        winehq-stable=${WINE_VERSION} \
        wine-stable=${WINE_VERSION} \
        wine-stable-amd64=${WINE_VERSION} \
        wine-stable-i386=${WINE_VERSION} \
    && rm -rf /var/lib/apt/lists/*

# winetricks depuis le dépôt amont, épinglé sur une version datée.
ARG WINETRICKS_VERSION=20260125
RUN wget -qO /usr/local/bin/winetricks \
        "https://raw.githubusercontent.com/Winetricks/winetricks/${WINETRICKS_VERSION}/src/winetricks" \
    && chmod +x /usr/local/bin/winetricks

# Copie de référence de SteamCMD : le volume partagé ~/volumes/steamcmd peut être
# vide au premier lancement, start_server.sh le remplit depuis cette copie.
RUN cp -a /home/steam/steamcmd /opt/steamcmd-template

# SAVE_DIR est monté DANS le dossier du serveur (DNL/Saved) : le jeu n'accepte
# pas de chemin de sauvegarde externe. Volume Docker distinct malgré tout.
ENV SERVER_DIR="/home/steam/dnl_server" \
    SAVE_DIR="/home/steam/dnl_server/DNL/Saved" \
    WINEPREFIX="/home/steam/wineprefix" \
    WINEARCH="win64" \
    WINEDEBUG="-all" \
    LANG="C.UTF-8"

RUN mkdir -p "$SERVER_DIR" "$SAVE_DIR" "$WINEPREFIX" \
    && chown -R steam:steam "$SERVER_DIR" "$WINEPREFIX"

COPY --chown=steam:steam start_server.sh healthcheck.sh /home/steam/
RUN chmod +x /home/steam/start_server.sh /home/steam/healthcheck.sh

WORKDIR /home/steam

# Ports officiels (documentation uniquement — c'est docker-compose qui publie) :
#   7777/udp jeu, 7778/udp raw (toujours jeu+1), 27015/udp requête Steam.
# Le port RCON (TCP) n'est pas listé : désactivé par défaut.
EXPOSE 7777/udp 7778/udp 27015/udp

# Socket UDP du port de requête ouverte = carte chargée, serveur à l'écoute.
# start-period long : le 1er démarrage télécharge le jeu et prépare Wine.
HEALTHCHECK --interval=60s --timeout=10s --start-period=60m --retries=3 \
    CMD /home/steam/healthcheck.sh

ENTRYPOINT ["/usr/bin/tini", "--", "/home/steam/start_server.sh"]
