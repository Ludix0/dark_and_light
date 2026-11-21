#!/bin/bash
# Dark and Light Dedicated Server — script de démarrage du conteneur.
#   1. Ajuste l'utilisateur steam sur PUID/PGID (seule partie exécutée en root)
#   2. Installe / met à jour le serveur via SteamCMD (3 essais max)
#   3. Initialise le préfixe Wine une seule fois (persistant en volume)
#   4. Écrit tous les réglages DNL_* dans GameUserSettings.ini
#   5. Lance le serveur sous l'utilisateur steam et gère l'arrêt propre (SIGTERM)

APP_ID=630230
GAME_PORT=${GAME_PORT:-7777}       # Le port raw est automatiquement GAME_PORT+1
QUERY_PORT=${QUERY_PORT:-27015}
RCON_PORT=${RCON_PORT:-27020}
EXE_DIR="${SERVER_DIR}/DNL/Binaries/Win64"
EXE="${EXE_DIR}/DNLServer.exe"
INI_DIR="${SAVE_DIR}/Config/WindowsServer"
GUS_INI="${INI_DIR}/GameUserSettings.ini"
STEAMCMD="/home/steam/steamcmd/steamcmd.sh"
PREFIX_MARKER="${WINEPREFIX}/.dnl_prefix_ready"

log() { echo "[start_server] $(date +%H:%M:%S) $*"; }
as_steam() { gosu steam env HOME=/home/steam "$@"; }

# ── 1. Ajustement UID/GID ──────────────────────────────────────────────────
USER_ID=${PUID:-1000}
GROUP_ID=${PGID:-1000}
log "Utilisateur steam -> UID ${USER_ID} / GID ${GROUP_ID}"
groupmod -o -g "$GROUP_ID" steam
usermod -o -u "$USER_ID" -g "$GROUP_ID" steam

# SteamCMD partagé : si le volume est vide, le remplir depuis la copie de l'image
if [ ! -x "$STEAMCMD" ]; then
    log "Volume SteamCMD vide, copie depuis l'image"
    cp -a /opt/steamcmd-template/. /home/steam/steamcmd/
fi

# On ne corrige les droits que s'il le faut (un chown -R sur plusieurs Go à
# chaque démarrage serait inutilement long).
for d in "$SERVER_DIR" "$SAVE_DIR" "$WINEPREFIX" /home/steam/steamcmd; do
    mkdir -p "$d"
    if [ "$(stat -c '%u:%g' "$d")" != "${USER_ID}:${GROUP_ID}" ] \
       || [ -n "$(find "$d" -xdev \( ! -uid "$USER_ID" -o ! -gid "$GROUP_ID" \) -print -quit 2>/dev/null)" ]; then
        log "Correction des droits sur $d"
        chown -R "${USER_ID}:${GROUP_ID}" "$d"
    fi
done
chown "${USER_ID}:${GROUP_ID}" /home/steam

# ── Xvfb (écran virtuel requis par Wine, winetricks et Unreal Engine) ──────
# Nettoyage des verrous laissés par un arrêt brutal (restart: unless-stopped
# relance le même conteneur, donc le même /tmp).
rm -f /tmp/.X99-lock /tmp/.X11-unix/X99
mkdir -p /tmp/.X11-unix && chmod 1777 /tmp/.X11-unix
as_steam Xvfb :99 -screen 0 1024x768x16 -nolisten tcp >/dev/null 2>&1 &
export DISPLAY=:99
for _ in $(seq 1 30); do [ -e /tmp/.X11-unix/X99 ] && break; sleep 1; done
[ -e /tmp/.X11-unix/X99 ] || { log "ERREUR : Xvfb n'a pas démarré"; exit 1; }

# ── 2. Installation / mise à jour via SteamCMD ────────────────────────────
# Connexion anonyme par défaut ; compte Steam réel uniquement si STEAM_USER
# est renseigné (voir docker-compose.yml).
if [ -n "$STEAM_USER" ]; then
    log "Connexion SteamCMD avec le compte : $STEAM_USER"
    LOGIN_ARGS=(+login "$STEAM_USER" "$STEAM_PASSWORD")
else
    LOGIN_ARGS=(+login anonymous)
fi

if [ "${UPDATE_ON_START:-true}" = "true" ] || [ ! -f "$EXE" ]; then
    ok=0
    for i in 1 2 3; do
        log "Mise à jour Dark and Light (App ${APP_ID}) — tentative ${i}/3"
        # Plateforme windows : il n'existe pas de version Linux de ce serveur.
        if as_steam "$STEAMCMD" \
            +@ShutdownOnFailedCommand 1 \
            +@NoPromptForPassword 1 \
            +@sSteamCmdForcePlatformType windows \
            +force_install_dir "$SERVER_DIR" \
            "${LOGIN_ARGS[@]}" \
            +app_update "$APP_ID" validate \
            +quit; then
            ok=1; break
        fi
        rm -rf "${SERVER_DIR}/steamapps/downloading" "${SERVER_DIR}/steamapps/temp"
        [ "$i" -lt 3 ] && { log "Échec, nouvel essai dans $((i * 15)) s"; sleep $((i * 15)); }
    done
    if [ "$ok" -ne 1 ]; then
        if [ -f "$EXE" ]; then
            log "ATTENTION : mise à jour impossible, démarrage sur la version déjà installée"
        else
            log "ERREUR : installation impossible après 3 essais"
            exit 1
        fi
    fi
else
    log "Mise à jour sautée (UPDATE_ON_START=false)"
fi

[ -f "$EXE" ] || { log "ERREUR : $EXE introuvable"; exit 1; }

# Le jeu cherche les DLL du client Steam à côté de DNLServer.exe, mais SteamCMD
# les dépose à la racine : sans cette copie, le serveur ne contacte jamais
# Steam (port de requête jamais ouvert, serveur absent de la liste).
# À refaire après chaque mise à jour (validate peut les retirer).
for dll in steamclient64.dll steamclient.dll tier0_s64.dll vstdlib_s64.dll; do
    [ -f "${SERVER_DIR}/${dll}" ] && as_steam cp -f "${SERVER_DIR}/${dll}" "${EXE_DIR}/${dll}"
done

# ── 3. Préfixe Wine (une seule fois, persistant) ──────────────────────────
# Unreal Engine 4 (2017) : runtimes Visual C++ 2013 et 2015-2019 x64.
# Chaque étape réussie laisse un marqueur : on reprend là où on s'était arrêté.
prefix_step() {
    local name=$1 max=$2; shift 2
    [ -f "${WINEPREFIX}/.step_${name}" ] && return 0
    log "Préfixe Wine : ${name} (max $((max / 60)) min)"
    if as_steam timeout "$max" "$@"; then
        as_steam timeout 300 wineserver -w
        as_steam touch "${WINEPREFIX}/.step_${name}"
        return 0
    fi
    log "ERREUR : étape '${name}' échouée ou trop longue"
    as_steam wineserver -k 2>/dev/null
    return 1
}

if [ ! -f "$PREFIX_MARKER" ]; then
    log "Initialisation du préfixe Wine (première fois : 5 à 15 minutes)"
    [ -f "${WINEPREFIX}/.step_wineboot" ] || rm -rf "${WINEPREFIX:?}/"* "${WINEPREFIX:?}"/.step_*
    prefix_step wineboot  600 env WINEDLLOVERRIDES="mscoree,mshtml=" wineboot --init || exit 1
    echo disable | as_steam tee "${WINEPREFIX}/.update-timestamp" >/dev/null
    prefix_step vcrun2013 900 winetricks -q vcrun2013 || exit 1
    prefix_step vcrun2019 900 winetricks -q vcrun2019 || exit 1
    prefix_step sound     300 winetricks -q sound=disabled || exit 1
    as_steam rm -rf /home/steam/.cache/winetricks
    as_steam touch "$PREFIX_MARKER"
    log "Préfixe Wine prêt"
else
    log "Préfixe Wine déjà initialisé"
fi

# ── 4. GameUserSettings.ini ───────────────────────────────────────────────
# Chaque variable d'environnement DNL_<Clé>=<valeur> devient la ligne
# <Clé>=<valeur> dans la section [ServerSettings]. Une valeur VIDE ne touche
# pas au fichier (le jeu garde sa valeur actuelle / par défaut).
# Les réglages du .ini l'emportent sur ceux de la ligne de lancement.
# Écriture via awk + ENVIRON : aucun souci d'échappement (|, &, /, espaces).
ini_set() {
    # $1 fichier, $2 section, $3 clé, $4 valeur
    INI_SECTION="$2" INI_KEY="$3" INI_VALUE="$4" awk '
        BEGIN { s="[" ENVIRON["INI_SECTION"] "]"; k=ENVIRON["INI_KEY"]; v=ENVIRON["INI_VALUE"]; insec=0; done=0 }
        {
            if ($0 ~ /^\[.*\][ \r]*$/) {
                if (insec && !done) { print k "=" v; done=1 }
                insec = ($0 == s || $0 == s "\r")
                print; next
            }
            if (insec && index($0, k "=") == 1) { if (!done) { print k "=" v; done=1 } ; next }
            print
        }
        END {
            if (!done) { if (!insec) print s; print k "=" v }
        }' "$1" > "$1.tmp" && cat "$1.tmp" > "$1" && rm -f "$1.tmp"
}

as_steam mkdir -p "$INI_DIR"
[ -f "$GUS_INI" ] || as_steam touch "$GUS_INI"

# Valeurs imposées par le conteneur. RCON est TOUJOURS actif : c'est lui qui
# permet l'arrêt propre (SaveWorld + DoExit), le jeu ignorant les signaux sous
# Wine. Il n'est joignable de l'extérieur que si son port est publié dans
# docker-compose.yml (ce qui n'est pas le cas par défaut).
unset DNL_RCONEnabled
ini_set "$GUS_INI" "ServerSettings" "RCONEnabled" "True"
ini_set "$GUS_INI" "ServerSettings" "RCONPort" "$RCON_PORT"

count=0
while IFS='=' read -r name _; do
    key="${name#DNL_}"
    value="${!name}"
    [ -z "$value" ] && continue
    ini_set "$GUS_INI" "ServerSettings" "$key" "$value"
    count=$((count + 1))
done < <(env | grep -E '^DNL_[A-Za-z0-9_]+=' | sort)

# Nom de session : section propre au moteur (affiché dans le navigateur Steam)
[ -n "$DNL_SessionName" ] && ini_set "$GUS_INI" "SessionSettings" "SessionName" "$DNL_SessionName"
[ -n "$DNL_MaxPlayers" ] && ini_set "$GUS_INI" "/Script/Engine.GameSession" "MaxPlayers" "$DNL_MaxPlayers"

chown "${USER_ID}:${GROUP_ID}" "$GUS_INI"
chmod 600 "$GUS_INI"   # contient les mots de passe
log "${count} réglage(s) DNL_* appliqué(s) dans GameUserSettings.ini"

# ── 5. Lancement et arrêt propre ──────────────────────────────────────────
case "${MAP:-TheSacredPath}" in
    TheSacredPath) MAP_PATH="/Game/DNL/Maps/CapeOfSacredPath/DNL_ALL" ;;
    TheShard)      MAP_PATH="/Game/TheShard/Maps/TheShard" ;;
    /Game/*)       MAP_PATH="$MAP" ;;   # chemin complet fourni tel quel
    *) log "ERREUR : MAP='${MAP}' inconnue (TheSacredPath, TheShard ou /Game/...)"; exit 1 ;;
esac

# Les mots de passe ne sont PAS passés en ligne de commande (visibles dans
# 'ps') : ils sont uniquement dans GameUserSettings.ini (chmod 600).
URL="${MAP_PATH}?listen?Port=${GAME_PORT}?QueryPort=${QUERY_PORT}?MultiHome=${MULTIHOME:-0.0.0.0}"
URL="${URL}?RCONEnabled=True?RCONPort=${RCON_PORT}"
[ -n "$DNL_SessionName" ] && URL="${URL}?SessionName=${DNL_SessionName}"
[ -n "$DNL_MaxPlayers" ] && URL="${URL}?MaxPlayers=${DNL_MaxPlayers}"
[ -n "$EXTRA_URL_OPTIONS" ] && URL="${URL}?${EXTRA_URL_OPTIONS#\?}"

# shellcheck disable=SC2206  # découpage volontaire des arguments supplémentaires
EXTRA=( ${EXTRA_ARGS} )

# ── Client RCON minimal (protocole Source RCON), en bash pur ───────────────
# Paquet : taille (int32 LE) | id (int32) | type (int32) | texte | \0\0
# type 3 = authentification, 2 = commande. Mot de passe = ServerAdminPassword.
rcon_packet() {
    local id=$1 type=$2 body=$3 size n out=""
    size=$(( 10 + ${#body} ))
    for n in "$size" "$id" "$type"; do
        out+=$(printf '\\x%02x\\x%02x\\x%02x\\x%02x' \
            $((n & 255)) $(((n >> 8) & 255)) $(((n >> 16) & 255)) $(((n >> 24) & 255)))
    done
    printf '%b' "$out"; printf '%s' "$body"; printf '\0\0'
}
rcon() {
    # $1 = commande ; affiche la réponse lisible du serveur
    exec 3<>"/dev/tcp/127.0.0.1/${RCON_PORT}" 2>/dev/null || { log "RCON injoignable"; return 1; }
    # Le serveur ignore une commande reçue avant la fin de l'authentification :
    # on attend donc la réponse à l'authentification (14 octets) avant d'envoyer.
    rcon_packet 1 3 "$DNL_ServerAdminPassword" >&3
    timeout 3 head -c 14 <&3 >/dev/null
    rcon_packet 2 2 "$1" >&3
    timeout 3 cat <&3 | tr -c '[:print:]\n' ' ' | tr -s ' ' | sed 's/^ *//'
    exec 3>&- 3<&-
}

# Le .exe Windows ignore SIGTERM/SIGINT sous Wine : l'arrêt propre passe par
# RCON (SaveWorld puis DoExit). SIGINT puis wineserver -k en dernier recours.
GAME_PATTERN='DNLServer\.exe'
game_running() { pgrep -f "$GAME_PATTERN" >/dev/null 2>&1; }

# Sous Wine, DoExit fait planter le jeu pendant sa fermeture (rapport
# « Fatal error » dans Saved/Logs) et le processus reste bloqué. Une fois la
# sauvegarde confirmée, on n'attend donc que 15 s avant de couper le jeu.
shutdown_server() {
    local timeout=${SHUTDOWN_TIMEOUT:-60} reply
    log "SIGTERM reçu : sauvegarde puis arrêt du serveur"
    reply=$(rcon SaveWorld)
    log "RCON SaveWorld : ${reply}"
    if [[ "$reply" == *"World Saved"* ]]; then
        timeout=15
    else
        log "ATTENTION : sauvegarde non confirmée, nouvel essai dans 5 s"
        sleep 5
        log "RCON SaveWorld : $(rcon SaveWorld)"
    fi
    sleep 5
    log "RCON DoExit : $(rcon DoExit) (attente max ${timeout} s)"
    for _ in $(seq 1 "$timeout"); do
        game_running || break
        sleep 1
    done
    if game_running; then
        log "Le jeu ne s'est pas fermé seul (plantage connu à la fermeture), arrêt forcé"
        # Envoyé en tant que steam : avec cap_drop ALL, root n'a plus CAP_KILL.
        as_steam pkill -INT -f "$GAME_PATTERN"
        sleep 3
        as_steam pkill -KILL -f "$GAME_PATTERN"
    fi
    as_steam timeout 10 wineserver -k 2>/dev/null
    log "Serveur arrêté"
    exit 0
}
trap shutdown_server SIGTERM SIGINT

# Nettoyage des rapports de plantage (un par arrêt, cf. shutdown_server) plus
# vieux que CRASH_REPORT_DAYS jours. Les journaux du jeu (*.log) sont conservés.
clean_crash_reports() {
    local days=${CRASH_REPORT_DAYS:-7} n
    n=$(as_steam find "${SAVE_DIR}/Logs" -maxdepth 1 -type f -mtime +"$days" \
        \( -name '*.crashstack' -o -name 'crashcallstack-*.txt' -o -name '*.dmp' \) \
        -print -delete 2>/dev/null | wc -l)
    log "Rapports de plantage de plus de ${days} jours supprimés : ${n}"
}
clean_crash_reports

cd "$EXE_DIR" || exit 1
log "Carte : ${MAP_PATH}"
log "Ports : jeu ${GAME_PORT}/udp, raw $((GAME_PORT + 1))/udp, requête ${QUERY_PORT}/udp, RCON ${RCON_PORT}/tcp (interne)"
as_steam wine "$EXE" "$URL" -server -game -log -nosteamclient "${EXTRA[@]}" &

# 'wine' peut confier le programme à un autre processus : on surveille donc le
# vrai .exe plutôt que le PID du lanceur. "wait" garde le trap réactif.
sleep 20
while game_running; do
    sleep 5 &
    wait $!
done
log "Le processus du serveur s'est terminé (voir DNL/Saved/Logs dans le volume saves)"
as_steam wineserver -k 2>/dev/null
exit 1
