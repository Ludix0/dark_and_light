#!/bin/bash
# Healthcheck : le serveur est "sain" quand il écoute sur son port de requête
# Steam UDP (QUERY_PORT, en hexadécimal dans /proc/net/udp). L'image n'a ni ss
# ni netstat. Ce port n'est ouvert qu'une fois la carte chargée : pendant le
# téléchargement SteamCMD et la préparation de Wine, le conteneur reste en "starting".
HEX=$(printf '%04X' "${QUERY_PORT:-27015}")
grep -qE "^ *[0-9]+: [0-9A-F]+:${HEX} " /proc/net/udp /proc/net/udp6 2>/dev/null
