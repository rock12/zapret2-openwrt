#!/bin/sh
# List auto-updater for zapret2 and warp games/telegram

ZAPRET2_DIR="${ZAPRET2_DIR:-/opt/zapret2}"
WARP_DIR="$ZAPRET2_DIR/warp"
GAMES_DIR="$WARP_DIR/games"
BASE_GAMES_URL="https://raw.githubusercontent.com/medvedeff-true/ru-gaming-blocklist/main"
LOG_FILE="/tmp/zapret2-update-lists.log"

_log() {
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG_FILE"
}

update_telegram_ips() {
    _log "Обновление пулов IP Telegram..."
    local dest="$WARP_DIR/telegram_ips.txt"
    local url="https://raw.githubusercontent.com/necronicle/z2k/z2k-enhanced/files/lists/telegram_ips.txt"
    local tmp="/tmp/tg_ips.tmp"
    if curl -sL -m 15 -o "$tmp" "$url" && [ -s "$tmp" ]; then
        mv "$tmp" "$dest"
        _log "Пулы IP Telegram успешно обновлены."
    else
        rm -f "$tmp"
        _log "Не удалось скачать IP Telegram, оставлен прежний список."
    fi
}

update_warp_games() {
    _log "Обновление игровых списков WARP..."
    mkdir -p "$GAMES_DIR"
    local idx="/tmp/games_sources.json"
    if ! curl -sL -m 20 -o "$idx" "$BASE_GAMES_URL/sources.json" || [ ! -s "$idx" ]; then
        _log "sources.json недоступен — пропуск обновления игровых списков."
        rm -f "$idx"
        return 1
    fi

    local names
    names=$(tr -d '\n' < "$idx" \
        | sed -n 's/.*"game_map"[[:space:]]*:[[:space:]]*{\([^}]*\)}.*/\1/p' \
        | grep -oE '"[^"]+"[[:space:]]*:' \
        | sed 's/^"//; s/"[[:space:]]*:$//' \
        | tr ' ' '_')

    for g in $names; do
        [ "$g" = "Other_Games" ] && continue
        case "$g" in ''|.*|-*|*[!A-Za-z0-9._-]*) continue ;; esac
        local tmp="/tmp/game_$g.tmp"
        if curl -sL -m 15 -o "$tmp" "$BASE_GAMES_URL/games/$g.txt" && [ -s "$tmp" ]; then
            mv "$tmp" "$GAMES_DIR/$g.txt"
        else
            rm -f "$tmp"
        fi
    done
    rm -f "$idx"
    _log "Игровые списки обновлены."
    
    # Reload PBR if warp is up
    if [ -x "$ZAPRET2_DIR/warp.sh" ]; then
        "$ZAPRET2_DIR/warp.sh" pbr_up >/dev/null 2>&1 || true
    fi
}

case "$1" in
    telegram) update_telegram_ips ;;
    games)    update_warp_games ;;
    all|'')   update_telegram_ips; update_warp_games ;;
    *) echo "usage: $0 {all|telegram|games}" >&2; exit 1 ;;
esac