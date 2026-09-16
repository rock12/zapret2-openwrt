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

# Configure OpenWrt interface 'warp'
warp_uci_setup() {
    [ -s "$WARP_DEV" ] || warp_register || return 1
    
    local priv v4 v6 ep host port
    priv=$(_json_val "$WARP_DEV" private_key)
    v4=$(_json_val "$WARP_DEV" v4)
    v6=$(_json_val "$WARP_DEV" v6)
    
    [ -s "$WARP_DIR/endpoint" ] || warp_scout >/dev/null
    ep=$(cat "$WARP_DIR/endpoint" 2>/dev/null || echo "162.159.192.1:2408")
    host="${ep%:*}"
    port="${ep##*:}"

    uci -q delete network.warp
    uci -q delete network.wireguard_warp
    
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

    uci commit network

    local wan_zone
    wan_zone=$(uci show firewall 2>/dev/null | grep '=zone' | grep -E "name='wan'" | cut -d. -f1,2)
    if [ -n "$wan_zone" ]; then
        uci add_list "$wan_zone.network"='warp' 2>/dev/null
        uci commit firewall
    fi
    _log "Интерфейс warp настроен в UCI."
    return 0
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
            for gfile in "$GAMES_DIR"/*.txt "$WARP_DIR/games_user.txt"; do
                [ -f "$gfile" ] || continue
                for cidr in $(grep -vE '^[[:space:]]*(#|$)' "$gfile" | grep -v ':'); do
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
    else
        ipset create warp_targets hash:net maxelem 65536 2>/dev/null || ipset flush warp_targets 2>/dev/null || true
        local route_games="$(uci -q get zapret2.config.WARP_GAMES || echo 1)"
        local route_tg="$(uci -q get zapret2.config.WARP_TELEGRAM || echo 1)"

        if [ "$route_tg" != "0" ] && [ -s "$TG_IPS" ]; then
            grep -vE '^[[:space:]]*(#|$)' "$TG_IPS" | grep -v ':' | while read -r c; do ipset add warp_targets "$c" 2>/dev/null; done
        fi
        if [ "$route_games" != "0" ]; then
            for gf in "$GAMES_DIR"/*.txt "$WARP_DIR/games_user.txt"; do
                [ -f "$gf" ] || continue
                grep -vE '^[[:space:]]*(#|$)' "$gf" | grep -v ':' | while read -r c; do ipset add warp_targets "$c" 2>/dev/null; done
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

case "$1" in
    register) warp_register ;;
    import)   shift; warp_import "$@" ;;
    scout)    warp_scout ;;
    up)       warp_up ;;
    down)     warp_down ;;
    pbr_up)   warp_pbr_up ;;
    pbr_down) warp_pbr_down ;;
    status)   warp_status ;;
    restart)  warp_down; warp_up ;;
    *) echo "usage: $0 {register|import|scout|up|down|restart|status}" >&2; exit 1 ;;
esac