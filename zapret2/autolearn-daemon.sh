#!/bin/sh
# Autolearn background daemon for zapret2
# Continuously monitors failed connections, resolves domains, aggregates CDN CIDRs,
# and applies fast tuning for problematic hosts.

AUTOHOSTS="/opt/zapret2/ipset/zapret-hosts-auto.txt"
AUTOHOSTS_DEBUG="/opt/zapret2/ipset/zapret-hosts-auto-debug.log"
MDIG="/opt/zapret2/mdig/mdig"
IP2NET="/opt/zapret2/ip2net/ip2net"
QUICK_TUNE="/opt/zapret2/quick-tune.sh"
CUSTOM_CONF="/opt/zapret2/custom_strats.txt"
LOGFILE="/tmp/zapret2_autolearn.log"
LOCKFILE="/tmp/zapret2_autolearn.lock"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [autolearn] $*" | tee -a "$LOGFILE"
}

# Ensure lock
if [ -f "$LOCKFILE" ]; then
    PID=$(cat "$LOCKFILE")
    if kill -0 "$PID" 2>/dev/null; then
        exit 0
    fi
fi
echo $$ > "$LOCKFILE"

trap "rm -f $LOCKFILE; exit 0" INT TERM EXIT

log "Демон автоматического обучения и агрегации подсетей запущен (PID: $$)"

# Process single domain
process_domain() {
    local domain="$1"
    [ -n "$domain" ] || return 0
    
    # Check if already processed in custom rules
    if grep -q "hostlist-domains=.*$domain" "$CUSTOM_CONF" 2>/dev/null; then
        return 0
    fi

    log "Обнаружен заблокированный ресурс: $domain"

    # 1. Resolve domain and find CDN IP blocks
    local tmp_ips="/tmp/autolearn_ips_$$.txt"
    local tmp_nets="/tmp/autolearn_nets_$$.txt"
    
    if [ -x "$MDIG" ]; then
        echo "$domain" | $MDIG --threads=1 --family=4 --pipe 2>/dev/null | awk '{print $2}' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' > "$tmp_ips"
    else
        nslookup "$domain" 127.0.0.1 2>/dev/null | awk '/^Address: / {print $2}' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' > "$tmp_ips"
    fi

    # 2. Aggregate CDN CIDR via ip2net
    if [ -s "$tmp_ips" ]; then
        if [ -x "$IP2NET" ]; then
            $IP2NET -4 --prefix-length=22-24 < "$tmp_ips" 2>/dev/null > "$tmp_nets"
        else
            awk '{print $1 "/32"}' "$tmp_ips" > "$tmp_nets"
        fi

        # Add resolved CIDRs to nftables set 'zapret' directly for both TCP and UDP
        while read -r cidr; do
            [ -n "$cidr" ] || continue
            nft add element inet zapret2 zapret { "$cidr" } 2>/dev/null || true
            log "Подсеть CDN $cidr добавлена в nftables (TCP/UDP)"
        done < "$tmp_nets"
    fi
    rm -f "$tmp_ips" "$tmp_nets"

    # 3. Quick-tune test if standard strategy failed
    if [ -x "$QUICK_TUNE" ]; then
        res=$($QUICK_TUNE "$domain" 2>/dev/null)
        if echo "$res" | grep -q "^SUCCESS:"; then
            strat_name=$(echo "$res" | cut -d':' -f3)
            strat_opt=$(echo "$res" | cut -d':' -f4-)
            log "Для $domain подобрана персональная стратегия DPI: $strat_name"
            
            # Record custom rule
            echo "--new --filter-tcp=443 --filter-l7=tls --hostlist-domains=$domain $strat_opt" >> "$CUSTOM_CONF"
            
            # Signal reload to zapret2
            /opt/zapret2/sync_config.sh 2>/dev/null || true
            /etc/init.d/zapret2 restart >/dev/null 2>&1 &
        else
            log "DPI стратегии не пробили $domain (вероятен бан по IP). Перенаправление в Cloudflare WARP..."
            
            # Route domain IP to WARP
            local warp_ip
            warp_ip=$(nslookup "$domain" 127.0.0.1 2>/dev/null | awk '/^Address: / {print $2}' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)
            [ -z "$warp_ip" ] && warp_ip=$(nslookup "$domain" 8.8.8.8 2>/dev/null | awk '/^Address: / {print $2}' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)
            
            if [ -n "$warp_ip" ]; then
                if [ -x "/opt/zapret2/warp.sh" ]; then
                    # Ensure WARP is running
                    if [ "$(uci -q get zapret2.config.WARP_ENABLED)" != "1" ]; then
                        uci set zapret2.config.WARP_ENABLED=1
                        uci commit zapret2
                    fi
                    /opt/zapret2/warp.sh up >/dev/null 2>&1 || true
                    /opt/zapret2/warp.sh add_target "$warp_ip/32"
                    log "IP $warp_ip для $domain успешно направлен в туннель WARP"
                fi
            fi
        fi
    fi
}

# Continuous loop monitoring
SEEN_FILE="/tmp/zapret2_autolearn_seen.txt"
touch "$SEEN_FILE"

while true; do
    # Check autohostlist for new additions
    if [ -s "$AUTOHOSTS" ]; then
        while read -r dom; do
            [ -n "$dom" ] || continue
            # Ignore comments
            echo "$dom" | grep -q '^#' && continue
            
            if ! grep -q "^$dom$" "$SEEN_FILE" 2>/dev/null; then
                echo "$dom" >> "$SEEN_FILE"
                process_domain "$dom"
            fi
        done < "$AUTOHOSTS"
    fi

    # Check debug log for instant triggers
    if [ -s "$AUTOHOSTS_DEBUG" ]; then
        dom=$(tail -n 1 "$AUTOHOSTS_DEBUG" | awk '{print $NF}')
        if [ -n "$dom" ] && ! grep -q "^$dom$" "$SEEN_FILE" 2>/dev/null; then
            echo "$dom" >> "$SEEN_FILE"
            process_domain "$dom"
        fi
    fi

    sleep 3
done
