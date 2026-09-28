#!/bin/sh
# List auto-updater for zapret2 and warp games/telegram
# Uses YOZH3G/ru-gaming-blocklist (the conservative, reviewed fork) with strict bogon/cloud filtering

ZAPRET2_DIR="${ZAPRET2_DIR:-/opt/zapret2}"
WARP_DIR="$ZAPRET2_DIR/warp"
GAMES_DIR="$WARP_DIR/games"
FILTER_AWK="$WARP_DIR/warp-list-filter.awk"
BASE_GAMES_URL="https://raw.githubusercontent.com/YOZH3G/ru-gaming-blocklist/main"
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
    _log "Обновление игровых списков WARP из YOZH3G/ru-gaming-blocklist..."
    mkdir -p "$GAMES_DIR"
    local idx="/tmp/games_sources.json"
    if ! curl -sL -m 20 -o "$idx" "$BASE_GAMES_URL/sources.json" || [ ! -s "$idx" ]; then
        _log "sources.json недоступен — пропуск обновления игровых списков."
        rm -f "$idx"
        return 1
    fi

    # 1. Update curated community game ipset
    local cur_ipset="/tmp/medvedeff_ipset.raw"
    if curl -sL -m 15 -o "$cur_ipset" "$BASE_GAMES_URL/medvedeff-game-ipset.txt" && [ -s "$cur_ipset" ]; then
        if [ -f "$FILTER_AWK" ]; then
            awk -v mode=ipset -f "$FILTER_AWK" "$cur_ipset" > "$GAMES_DIR/Community_Gaming_IPs.txt" 2>/dev/null
        else
            grep -E '^[0-9]' "$cur_ipset" > "$GAMES_DIR/Community_Gaming_IPs.txt"
        fi
        rm -f "$cur_ipset"
        _log "Обновлен общий чистый игровой пул Community_Gaming_IPs.txt ($(wc -l < "$GAMES_DIR/Community_Gaming_IPs.txt") подсетей)."
    fi

    # 2. Extract game names
    local names
    names=$(tr -d '\n' < "$idx" \
        | sed -n 's/.*"game_map"[[:space:]]*:[[:space:]]*{\([^}]*\)}.*/\1/p' \
        | grep -oE '"[^"]+"[[:space:]]*:' \
        | sed 's/^"//; s/"[[:space:]]*:$//' \
        | tr ' ' '_')

    for g in $names; do
        # Strictly skip general-purpose cloud providers and catch-alls
        [ "$g" = "Other_Games" ] && continue
        [ "$g" = "Cloudflare_AWS" ] && continue
        case "$g" in ''|.*|-*|*[!A-Za-z0-9._-]*) continue ;; esac

        local raw="/tmp/game_${g}.raw"
        local san="/tmp/game_${g}.san"
        if curl -sL -m 15 -o "$raw" "$BASE_GAMES_URL/games/$g.txt" && [ -s "$raw" ]; then
            if [ -f "$FILTER_AWK" ]; then
                awk -v mode=save -f "$FILTER_AWK" "$raw" > "$san" 2>/dev/null
                if [ -s "$san" ]; then
                    mv "$san" "$GAMES_DIR/$g.txt"
                else
                    rm -f "$san"
                fi
            else
                mv "$raw" "$GAMES_DIR/$g.txt"
            fi
            rm -f "$raw"
        else
            rm -f "$raw"
        fi
    done
    rm -f "$idx"
    _log "Игровые списки обновлены и очищены от паразитных подсетей."
    
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