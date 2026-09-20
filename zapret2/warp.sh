#!/bin/sh
# OpenWrt Cloudflare WARP manager for zapret2
# Handles free device registration, endpoint scouting, and PBR routing for Games & Telegram.

ZAPRET2_DIR="${ZAPRET2_DIR:-/opt/zapret2}"
WARP_DIR="$ZAPRET2_DIR/warp"
WARP_DEV="$WARP_DIR/device.json"
WARP_LOG="/tmp/zapret2-warp.log"
WARP_TABLE="100"
FWMARK="0x1000"

CF_PUBKEY="bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo="
GAMES_DIR="$WARP_DIR/games"
TG_IPS="$WARP_DIR/telegram_ips.txt"
ENDPOINTS_FILE="$WARP_DIR/warp-endpoints.txt"

_log() {
    printf '%s [warp] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$WARP_LOG"
}

_json_val() {
    sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$1" 2>/dev/null | head -n1
}

# Generate 32-byte base64 private key
gen_private_key() {
    if command -v wg >/dev/null 2>&1; then
        wg genkey
    elif command -v openssl >/dev/null 2>&1; then
        openssl rand -base64 32
    else
        head -c 32 /dev/urandom | base64 | tr -d '\n'
    fi
}

# Derive public key from private key
derive_public_key() {
    local priv="$1"
    if command -v wg >/dev/null 2>&1; then
        printf '%s' "$priv" | wg pubkey
    else
        printf '%s' "$priv"
    fi
}

# Register free account on Cloudflare API
warp_register() {
    mkdir -p "$WARP_DIR"
    _log "Регистрация нового бесплатного устройства в Cloudflare WARP..."
    
    # 1. Автоматический генератор-зеркало (обходит блокировку api.cloudflareclient.com в РФ)
    local resp
    resp=$(curl -sL -m 8 "https://generator-config-warp.vercel.app/api/warp-data" 2>/dev/null)
    local priv v4 v6
    priv=$(printf '%s' "$resp" | sed -n 's/.*"privKey"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    v4=$(printf '%s' "$resp" | sed -n 's/.*"client_ipv4"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    v6=$(printf '%s' "$resp" | sed -n 's/.*"client_ipv6"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    
    if [ -n "$priv" ] && [ -n "$v4" ]; then
        cat > "$WARP_DEV" <<-EOF
{
  "private_key": "$priv",
  "v4": "$v4",
  "v6": "${v6:-2606:4700:110:801f:ef38:34a9:84bc:a5a0}"
}
EOF
        chmod 600 "$WARP_DEV"
        _log "Устройство успешно зарегистрировано автоматически! IP: $v4"
        return 0
    fi

    # 2. Официальный API Cloudflare (резервный метод)
    priv=$(gen_private_key)
    local pub
    pub=$(derive_public_key "$priv")

    local json_req
    json_req="{\"key\":\"$pub\",\"install_id\":\"\",\"fcm_token\":\"\",\"tos\":\"$(date -u +'%Y-%m-%dT%H:%M:%S.000Z')\",\"model\":\"OpenWrt\",\"type\":\"Android\",\"locale\":\"en_US\"}"
    
    resp=$(curl -s -m 15 -X POST -H "Content-Type: application/json; charset=UTF-8" \
        -H "User-Agent: okhttp/3.12.1" \
        -d "$json_req" \
        "https://api.cloudflareclient.com/v0a3118/reg" 2>/dev/null)

    local dev_id token
    dev_id=$(printf '%s' "$resp" | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    token=$(printf '%s' "$resp" | sed -n 's/.*"token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    v4=$(printf '%s' "$resp" | sed -n 's/.*"v4"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    v6=$(printf '%s' "$resp" | sed -n 's/.*"v6"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

    if [ -z "$v4" ]; then
        _log "ОШИБКА: Не удалось автоматически зарегистрировать устройство в WARP"
        return 1
    fi

    cat > "$WARP_DEV" <<-EOF
{
  "device_id": "$dev_id",
  "token": "$token",
  "private_key": "$priv",
  "public_key": "$pub",
  "v4": "$v4",
  "v6": "$v6"
}
EOF
    chmod 600 "$WARP_DEV"
    _log "Устройство успешно зарегистрировано! IP: $v4"
    return 0
}

# Import config from WARP Generator (warp-generation.github.io) or .conf file
warp_import() {
    local src="$1"
    mkdir -p "$WARP_DIR"
    
    local priv="" v4="" v6="" ep=""
    
    if [ -f "$src" ]; then
        # Parse standard WireGuard .conf file from warp-generation.github.io
        priv=$(grep -iE '^[[:space:]]*PrivateKey' "$src" | cut -d= -f2 | tr -d ' \r\t')
        local addrs
        addrs=$(grep -iE '^[[:space:]]*Address' "$src" | cut -d= -f2 | tr -d ' \r\t')
        v4=$(echo "$addrs" | tr ',' '\n' | grep -v ':' | head -n1 | cut -d/ -f1)
        v6=$(echo "$addrs" | tr ',' '\n' | grep ':' | head -n1 | cut -d/ -f1)
        ep=$(grep -iE '^[[:space:]]*Endpoint' "$src" | cut -d= -f2 | tr -d ' \r\t')
    elif [ -n "$src" ] && [ -n "$2" ]; then
        # Direct arguments: warp_import <private_key> <v4_ip> [v6_ip] [endpoint]
        priv="$1"
        v4="${2%/*}"
        v6="${3%/*}"
        ep="$4"
    else
        echo "Использование: $0 import </path/to/warp.conf> ИЛИ $0 import <private_key> <v4_ip> [v6_ip] [endpoint]"
        return 1
    fi
    
    if [ -z "$priv" ] || [ -z "$v4" ]; then
        _log "ОШИБКА: Не удалось извлечь PrivateKey и Address"
        return 1
    fi
    
    cat > "$WARP_DEV" <<-EOF
{
  "private_key": "$priv",
  "v4": "$v4",
  "v6": "${v6:-2606:4700:110:801f:ef38:34a9:84bc:a5a0}"
}
EOF
    chmod 600 "$WARP_DEV"
    [ -n "$ep" ] && echo "$ep" > "$WARP_DIR/endpoint"
    _log "Конфиг WARP успешно импортирован! IP: $v4"
    return 0
}

# Scout alive, unblocked endpoint with lowest ping for gaming
warp_scout() {
    _log "Поиск эндпоинта Cloudflare с наименьшим пингом (gaming latency scout)..."
    local candidates="8.34.70.1 8.34.70.2 8.34.70.3 8.34.70.4 8.34.70.10 162.159.192.1 162.159.192.2 162.159.193.1 162.159.193.5 162.159.195.1 188.114.96.1 188.114.97.1 162.159.192.10"
    if [ -s "$ENDPOINTS_FILE" ]; then
        candidates="$(grep -vE '^[[:space:]]*(#|$)' "$ENDPOINTS_FILE" | cut -d: -f1 | head -n 30) $candidates"
    fi

    local best_ip=""
    local best_ping=999999
    local best_port=2408
    local results=""

    for ip in $candidates; do
        local ping_out rtt
        ping_out=$(ping -c 2 -W 1 "$ip" 2>/dev/null)
        rtt=$(printf '%s\n' "$ping_out" | awk -F'/' '/avg|round-trip|rtt/ {printf "%d", $5}')
        
        if [ -n "$rtt" ] && [ "$rtt" -gt 0 ]; then
            _log "Кандидат $ip -> пинг ${rtt}ms"
            results="${results}${rtt}ms $ip\n"
            if [ "$rtt" -lt "$best_ping" ]; then
                best_ping=$rtt
                best_ip=$ip
                best_port=2408
            fi
        fi
    done

    local best_ep=""
    if [ -n "$best_ip" ]; then
        best_ep="$best_ip:$best_port"
        _log "Выбран наилучший игровой эндпоинт: $best_ep (минимальный пинг: ${best_ping}ms)"
    else
        best_ep="8.34.70.2:2408"
        _log "ICMP пинг не ответил, использован проверенный эндпоинт: $best_ep"
    fi

    printf '%s\n' "$best_ep" > "$WARP_DIR/endpoint"
    
    # If wireguard is already configured in UCI, update it live
    if uci -q get network.wireguard_warp >/dev/null; then
        uci set network.wireguard_warp.endpoint_host="${best_ep%:*}"
        uci set network.wireguard_warp.endpoint_port="${best_ep##*:}"
        uci commit network
        ifup warp 2>/dev/null || true
    fi

    echo "--- Топ эндпоинтов по пингу ---"
    printf "$results" | sort -n | head -n 5
    echo "Лучший эндпоинт: $best_ep (${best_ping}ms)"
}

# Check and automatically install WireGuard packages if missing
check_install_deps() {
    if ! command -v wg >/dev/null 2>&1 || [ ! -e /sys/module/wireguard ]; then
        _log "Проверка зависимостей: установка wireguard пакетов..."
        if command -v apk >/dev/null 2>&1; then
            apk update && apk add wireguard-tools kmod-wireguard luci-proto-wireguard 2>&1 | tee -a "$WARP_LOG"
        elif command -v opkg >/dev/null 2>&1; then
            opkg update && opkg install wireguard-tools kmod-wireguard luci-proto-wireguard 2>&1 | tee -a "$WARP_LOG"
        fi
    fi
}

# Configure OpenWrt interface 'warp'
warp_uci_setup() {
    check_install_deps
    
    local priv v4 v6 ep host port
    local has_awg=0
    if [ -x /usr/bin/awg ] && [ -r /root/WARP.conf ]; then
        has_awg=1
    fi

    if [ "$has_awg" = "1" ]; then
        _log "Настройка WARP с обфускацией AmneziaWG (пробитие блокировок DPI в РФ)..."
        local jc jmin jmax s1 s2 h1 h2 h3 h4 i1
        eval "$(awk '
        BEGIN{ sec="" }
        {
          line=$0; sub(/[;#].*$/, "", line); gsub(/^[ \t]+|[ \t]+$/, "", line)
          if (line=="") next
          if (line ~ /^\[.*\]$/) { sec=tolower(substr(line,2,length(line)-2)); next }
          idx=index(line,"="); if (idx==0) next
          k=tolower(substr(line,1,idx-1)); v=substr(line,idx+1)
          gsub(/^[ \t]+|[ \t]+$/, "", k); gsub(/^[ \t]+|[ \t]+$/, "", v)
          if (sec=="interface") {
            if (k=="privatekey") print "priv=\"" v "\""
            if (k=="address") print "addr=\"" v "\""
            if (k=="mtu") print "mtu=\"" v "\""
            if (k=="jc") print "jc=\"" v "\""
            if (k=="jmin") print "jmin=\"" v "\""
            if (k=="jmax") print "jmax=\"" v "\""
            if (k=="s1") print "s1=\"" v "\""
            if (k=="s2") print "s2=\"" v "\""
            if (k=="h1") print "h1=\"" v "\""
            if (k=="h2") print "h2=\"" v "\""
            if (k=="h3") print "h3=\"" v "\""
            if (k=="h4") print "h4=\"" v "\""
            if (k=="i1") print "i1=\"" v "\""
          } else if (sec=="peer") {
            if (k=="publickey") print "pub=\"" v "\""
            if (k=="endpoint") print "ep=\"" v "\""
          }
        }
        ' /root/WARP.conf)"

        host="${ep%:*}"
        port="${ep##*:}"
        v4="172.16.0.2"
        v6="2606:4700:110:8a97:2d25:5c57:21d0:1444"

        uci -q delete network.warp
        uci -q delete network.amneziawg_warp
        uci -q delete network.wireguard_warp

        uci set network.warp=interface
        uci set network.warp.proto='amneziawg'
        uci set network.warp.private_key="$priv"
        uci set network.warp.mtu="${mtu:-1280}"
        uci add_list network.warp.addresses="${v4}/32"
        uci add_list network.warp.addresses="${v6}/128"
        [ -n "$jc" ] && uci set network.warp.awg_jc="$jc"
        [ -n "$jmin" ] && uci set network.warp.awg_jmin="$jmin"
        [ -n "$jmax" ] && uci set network.warp.awg_jmax="$jmax"
        [ -n "$s1" ] && uci set network.warp.awg_s1="$s1"
        [ -n "$s2" ] && uci set network.warp.awg_s2="$s2"
        [ -n "$h1" ] && uci set network.warp.awg_h1="$h1"
        [ -n "$h2" ] && uci set network.warp.awg_h2="$h2"
        [ -n "$h3" ] && uci set network.warp.awg_h3="$h3"
        [ -n "$h4" ] && uci set network.warp.awg_h4="$h4"
        [ -n "$i1" ] && uci set network.warp.awg_i1="$i1"

        uci set network.amneziawg_warp=amneziawg_warp
        uci set network.amneziawg_warp.name='warp_peer'
        uci set network.amneziawg_warp.public_key="${pub:-$CF_PUBKEY}"
        uci set network.amneziawg_warp.endpoint_host="$host"
        uci set network.amneziawg_warp.endpoint_port="$port"
        uci set network.amneziawg_warp.route_allowed_ips='0'
        uci set network.amneziawg_warp.persistent_keepalive='25'
        uci add_list network.amneziawg_warp.allowed_ips='0.0.0.0/0'
        uci add_list network.amneziawg_warp.allowed_ips='::/0'
    else
        [ -s "$WARP_DEV" ] || warp_register || return 1
        priv=$(_json_val "$WARP_DEV" private_key)
        v4=$(_json_val "$WARP_DEV" v4)
        v6=$(_json_val "$WARP_DEV" v6)
        
        [ -s "$WARP_DIR/endpoint" ] || warp_scout >/dev/null
        ep=$(cat "$WARP_DIR/endpoint" 2>/dev/null || echo "162.159.192.1:2408")
        host="${ep%:*}"
        port="${ep##*:}"

        uci -q delete network.warp
        uci -q delete network.wireguard_warp
        uci -q delete network.amneziawg_warp
        
        uci set network.warp=interface
        uci set network.warp.proto='wireguard'
        uci set network.warp.private_key="$priv"
        uci add_list network.warp.addresses="${v4}/32"
        [ -n "$v6" ] && uci add_list network.warp.addresses="${v6}/128"
        uci set network.warp.disabled='0'

        uci set network.wireguard_warp=wireguard_warp
        uci set network.wireguard_warp.name='warp_peer'
        uci set network.wireguard_warp.public_key="$CF_PUBKEY"
        uci set network.wireguard_warp.endpoint_host="$host"
        uci set network.wireguard_warp.endpoint_port="$port"
        uci set network.wireguard_warp.route_allowed_ips='0'
        uci set network.wireguard_warp.persistent_keepalive='25'
        uci add_list network.wireguard_warp.allowed_ips='0.0.0.0/0'
        uci add_list network.wireguard_warp.allowed_ips='::/0'
    fi

    uci commit network

    local wan_zone
    wan_zone=$(uci show firewall 2>/dev/null | grep 'name=.wan.' | cut -d. -f1,2 | head -n1)
    if [ -n "$wan_zone" ]; then
        if ! uci -q get "$wan_zone.network" | grep -qw 'warp'; then
            uci add_list "$wan_zone.network"='warp' 2>/dev/null
            uci commit firewall
            /etc/init.d/firewall reload 2>/dev/null || true
        fi
    fi
    _log "Интерфейс warp настроен в UCI."
    return 0
}

game_uci_opt() {
    local gbase="$1"
    case "$gbase" in
        Warzone_CallOfDuty)        echo "WARP_GAME_WARZONE" ;;
        Battlefield6)              echo "WARP_GAME_BATTLEFIELD6" ;;
        Steam)                     echo "WARP_GAME_STEAM" ;;
        EA_Origin)                 echo "WARP_GAME_EA_ORIGIN" ;;
        BattleNet)                 echo "WARP_GAME_BATTLENET" ;;
        EpicGames_Fortnite)        echo "WARP_GAME_EPIC_FORTNITE" ;;
        RiotGames_Valorant)        echo "WARP_GAME_RIOT_VALORANT" ;;
        ApexLegends_RocketLeague)  echo "WARP_GAME_APEX_ROCKETLEAGUE" ;;
        Ubisoft_Rainbow_Six_Siege) echo "WARP_GAME_UBISOFT" ;;
        Roblox)                    echo "WARP_GAME_ROBLOX" ;;
        LeagueOfLegends)           echo "WARP_GAME_LEAGUEOFLEGENDS" ;;
        Warframe)                  echo "WARP_GAME_WARFRAME" ;;
        DeadByDaylight)            echo "WARP_GAME_DEADBYDAYLIGHT" ;;
        ArmaReforger)              echo "WARP_GAME_ARMA_REFORGER" ;;
        Minecraft_Extra)           echo "WARP_GAME_MINECRAFT" ;;
        *)
            local clean_name
            clean_name=$(echo "$gbase" | tr 'a-z' 'A-Z' | tr -c 'A-Z0-9_' '_')
            echo "WARP_GAME_$clean_name"
            ;;
    esac
}

# Setup PBR routing tables and rules
warp_pbr_up() {
    _log "Активация PBR маршрутизации в WARP (таблица $WARP_TABLE)..."
    
    ip route replace default dev warp table "$WARP_TABLE" 2>/dev/null || true
    ip rule del fwmark "$FWMARK" table "$WARP_TABLE" 2>/dev/null || true
    ip rule add fwmark "$FWMARK" table "$WARP_TABLE" pref 1000

    if [ -x /sbin/fw4 ]; then
        nft add table inet zapret2_warp 2>/dev/null || true
        nft flush table inet zapret2_warp 2>/dev/null || true
        nft add set inet zapret2_warp warp_targets '{ type ipv4_addr; flags interval; }' 2>/dev/null || true
        
        local route_games="$(uci -q get zapret2.config.WARP_GAMES || echo 1)"
        local route_tg="$(uci -q get zapret2.config.WARP_TELEGRAM || echo 1)"

        local tmp_nft="/tmp/warp_targets.nft"
        printf 'add element inet zapret2_warp warp_targets { ' > "$tmp_nft"
        local first=1
        
        if [ "$route_tg" != "0" ] && [ -s "$TG_IPS" ]; then
            for cidr in $(grep -vE '^[[:space:]]*(#|$)' "$TG_IPS" | grep -v ':'); do
                [ "$first" = 1 ] || printf ', ' >> "$tmp_nft"
                first=0
                printf '%s' "$cidr" >> "$tmp_nft"
            done
        fi
        
        if [ "$route_games" != "0" ]; then
            # 1. Custom user games
            if [ "$(uci -q get zapret2.config.WARP_GAME_CUSTOM || echo 1)" != "0" ] && [ -f "$WARP_DIR/games_user.txt" ]; then
                for cidr in $(grep -vE '^[[:space:]]*(#|$)' "$WARP_DIR/games_user.txt" | grep -v ':'); do
                    [ "$first" = 1 ] || printf ', ' >> "$tmp_nft"
                    first=0
                    printf '%s' "$cidr" >> "$tmp_nft"
                done
            fi

            # 2. Check each game file in $GAMES_DIR against individual UCI toggles
            for gfile in "$GAMES_DIR"/*.txt; do
                [ -f "$gfile" ] || continue
                local gbase opt is_enabled
                gbase="$(basename "$gfile" .txt)"
                opt=$(game_uci_opt "$gbase")
                is_enabled=$(uci -q get "zapret2.config.$opt")
                if [ "$is_enabled" != "0" ]; then
                    _log "Маршрутизация WARP ВКЛЮЧЕНА для: $gbase"
                    for cidr in $(grep -vE '^[[:space:]]*(#|$)' "$gfile" | grep -v ':'); do
                        [ "$first" = 1 ] || printf ', ' >> "$tmp_nft"
                        first=0
                        printf '%s' "$cidr" >> "$tmp_nft"
                    done
                else
                    _log "Маршрутизация WARP ВЫКЛЮЧЕНА для: $gbase"
                fi
            done

            # 3. Dynamic failover targets
            for autotgt in "$WARP_DIR/auto_targets.txt" /tmp/warp_targets.txt; do
                [ -f "$autotgt" ] || continue
                for cidr in $(grep -vE '^[[:space:]]*(#|$)' "$autotgt" | grep -v ':'); do
                    [ "$first" = 1 ] || printf ', ' >> "$tmp_nft"
                    first=0
                    printf '%s' "$cidr" >> "$tmp_nft"
                done
            done
        fi

        if [ "$first" = 0 ]; then
            printf ' }\n' >> "$tmp_nft"
            nft -f "$tmp_nft" 2>/dev/null || true
        fi
        rm -f "$tmp_nft"

        nft add chain inet zapret2_warp prerouting '{ type filter hook prerouting priority mangle - 1; }' 2>/dev/null || true
        nft add rule inet zapret2_warp prerouting ip daddr @warp_targets meta mark set "$FWMARK" 2>/dev/null || true
        nft add chain inet zapret2_warp output '{ type filter hook output priority mangle - 1; }' 2>/dev/null || true
        nft add rule inet zapret2_warp output ip daddr @warp_targets meta mark set "$FWMARK" 2>/dev/null || true
    else
        ipset create warp_targets hash:net maxelem 65536 2>/dev/null || ipset flush warp_targets 2>/dev/null || true
        local route_games="$(uci -q get zapret2.config.WARP_GAMES || echo 1)"
        local route_tg="$(uci -q get zapret2.config.WARP_TELEGRAM || echo 1)"

        if [ "$route_tg" != "0" ] && [ -s "$TG_IPS" ]; then
            grep -vE '^[[:space:]]*(#|$)' "$TG_IPS" | grep -v ':' | while read -r c; do ipset add warp_targets "$c" 2>/dev/null; done
        fi
        if [ "$route_games" != "0" ]; then
            if [ "$(uci -q get zapret2.config.WARP_GAME_CUSTOM || echo 1)" != "0" ] && [ -f "$WARP_DIR/games_user.txt" ]; then
                grep -vE '^[[:space:]]*(#|$)' "$WARP_DIR/games_user.txt" | grep -v ':' | while read -r c; do ipset add warp_targets "$c" 2>/dev/null; done
            fi
            for gf in "$GAMES_DIR"/*.txt; do
                [ -f "$gf" ] || continue
                local gb opt is_en
                gb="$(basename "$gf" .txt)"
                opt=$(game_uci_opt "$gb")
                is_en=$(uci -q get "zapret2.config.$opt")
                if [ "$is_en" != "0" ]; then
                    grep -vE '^[[:space:]]*(#|$)' "$gf" | grep -v ':' | while read -r c; do ipset add warp_targets "$c" 2>/dev/null; done
                fi
            done
        fi
        iptables -t mangle -D PREROUTING -m set --match-set warp_targets dst -j MARK --set-mark "$FWMARK" 2>/dev/null || true
        iptables -t mangle -A PREROUTING -m set --match-set warp_targets dst -j MARK --set-mark "$FWMARK" 2>/dev/null || true
    fi
    _log "PBR правила для Игр и Telegram успешно применены."
}

warp_pbr_down() {
    _log "Отключение PBR маршрутизации WARP..."
    ip rule del fwmark "$FWMARK" table "$WARP_TABLE" 2>/dev/null || true
    ip route flush table "$WARP_TABLE" 2>/dev/null || true
    
    if [ -x /sbin/fw4 ]; then
        nft delete table inet zapret2_warp 2>/dev/null || true
    else
        iptables -t mangle -D PREROUTING -m set --match-set warp_targets dst -j MARK --set-mark "$FWMARK" 2>/dev/null || true
        ipset destroy warp_targets 2>/dev/null || true
    fi
}

warp_up() {
    [ -s "$WARP_DEV" ] || warp_register || return 1
    warp_uci_setup
    ifup warp 2>/dev/null || true
    sleep 2
    warp_pbr_up
}

warp_down() {
    warp_pbr_down
    ifdown warp 2>/dev/null || true
}

warp_status() {
    local has_dev=0 is_up=0 ep=""
    [ -s "$WARP_DEV" ] && has_dev=1
    ip link show dev warp 2>/dev/null | grep -q "UP" && is_up=1
    [ -s "$WARP_DIR/endpoint" ] && ep=$(cat "$WARP_DIR/endpoint" 2>/dev/null)
    printf 'registered=%d connected=%d endpoint=%s\n' "$has_dev" "$is_up" "$ep"
}

# Dynamically route an IP/CIDR to WARP
warp_add_target() {
    local target="$1"
    [ -n "$target" ] || return 1
    
    mkdir -p "$WARP_DIR"
    touch "$WARP_DIR/auto_targets.txt"
    if ! grep -q "^$target$" "$WARP_DIR/auto_targets.txt" 2>/dev/null; then
        echo "$target" >> "$WARP_DIR/auto_targets.txt"
    fi

    ip route replace default dev warp table "$WARP_TABLE" 2>/dev/null || true

    if [ -x /sbin/fw4 ]; then
        nft add table inet zapret2_warp 2>/dev/null || true
        nft add set inet zapret2_warp warp_targets '{ type ipv4_addr; flags interval; }' 2>/dev/null || true
        nft add element inet zapret2_warp warp_targets { "$target" } 2>/dev/null || true
        nft add chain inet zapret2_warp prerouting '{ type filter hook prerouting priority mangle - 1; policy accept; }' 2>/dev/null || true
        nft add rule inet zapret2_warp prerouting ip daddr @warp_targets meta mark set "$FWMARK" 2>/dev/null || true
        nft add chain inet zapret2_warp output '{ type filter hook output priority mangle - 1; policy accept; }' 2>/dev/null || true
        nft add rule inet zapret2_warp output ip daddr @warp_targets meta mark set "$FWMARK" 2>/dev/null || true
    else
        ipset add warp_targets "$target" 2>/dev/null || true
    fi
    _log "Добавлен динамический маршрут в WARP: $target"
}

case "$1" in
    register)   warp_register ;;
    import)     shift; warp_import "$@" ;;
    scout)      warp_scout ;;
    up)         warp_up ;;
    down)       warp_down ;;
    pbr_up)     warp_pbr_up ;;
    pbr_down)   warp_pbr_down ;;
    status)     warp_status ;;
    add_target) shift; warp_add_target "$@" ;;
    reload)     warp_pbr_up ;;
    restart)    warp_down; warp_up ;;
    *) echo "usage: $0 {register|import|scout|up|down|reload|restart|status|add_target}" >&2; exit 1 ;;
esac