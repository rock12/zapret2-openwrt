#!/bin/sh
# Dedicated Autolearn & IPCIDR Subnet Manager for zapret2
# Detects failed domains, resolves IPs, aggregates CIDR subnets,
# adds them to nftables (TCP & UDP), and routes IP-blocked targets to WARP.
# Strictly excludes Russian national domains (.ru, .su, .рф, .дети).

AUTOHOSTS="/opt/zapret2/ipset/zapret-hosts-auto.txt"
AUTOHOSTS_DEBUG="/opt/zapret2/ipset/zapret-hosts-auto-debug.log"
AUTO_CIDR_LIST="/opt/zapret2/ipset/zapret-hosts-auto-cidr.txt"
MDIG="/opt/zapret2/mdig/mdig"
IP2NET="/opt/zapret2/ip2net/ip2net"
WARP_SH="/opt/zapret2/warp.sh"
LOGFILE="/tmp/zapret2_autolearn.log"
LOCKFILE="/tmp/zapret2_autolearn.lock"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [autolearn-cidr] $*" | tee -a "$LOGFILE"
}

is_russian_domain() {
    case "$1" in
        *.ru|*.su|*.xn--p1ai|*.xn--d1acj3b|*.рф|*.дети)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Resolve and determine all IP addresses and CIDR subnets for a domain
resolve_and_learn() {
    local domain="$1"
    [ -n "$domain" ] || return 0

    # 1. Strictly skip Russian domains
    if is_russian_domain "$domain"; then
        log "Пропуск: Национальный домен РФ ($domain)"
        return 0
    fi

    # Strip protocol or trailing slashes if passed as URL
    domain=$(echo "$domain" | sed -e 's|^[^/]*//||' -e 's|/.*$||' -e 's|:.*$||' | tr '[:upper:]' '[:lower:]')

    log "=== Определение домена и CIDR подсетей: $domain ==="

    local tmp_ips="/tmp/cidr_ips_$$.txt"
    local tmp_nets="/tmp/cidr_nets_$$.txt"
    : > "$tmp_ips"
    : > "$tmp_nets"

    # Resolve IPv4 addresses
    if [ -x "$MDIG" ]; then
        echo "$domain" | $MDIG --family=4 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' >> "$tmp_ips"
    fi
    if [ ! -s "$tmp_ips" ]; then
        nslookup "$domain" 127.0.0.1 2>/dev/null | awk '/^Address: / {print $2}' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' >> "$tmp_ips"
    fi
    if [ ! -s "$tmp_ips" ]; then
        nslookup "$domain" 8.8.8.8 2>/dev/null | awk '/^Address: / {print $2}' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' >> "$tmp_ips"
    fi

    sort -u -o "$tmp_ips" "$tmp_ips"

    if [ ! -s "$tmp_ips" ]; then
        log "ОШИБКА: Не удалось разрешить IP-адреса для $domain"
        rm -f "$tmp_ips" "$tmp_nets"
        return 1
    fi

    local ip_count
    ip_count=$(wc -l < "$tmp_ips")
    log "Найдено IP адресов ($domain): $ip_count"

    # Compute CIDR subnets (/24 or /32)
    while read -r ip; do
        [ -n "$ip" ] || continue
        # Calculate /24 network prefix for CDN aggregation
        local cdn_net
        cdn_net=$(echo "$ip" | cut -d'.' -f1-3).0/24
        echo "$cdn_net" >> "$tmp_nets"
        echo "$ip" >> "$tmp_nets"
    done < "$tmp_ips"

    sort -u -o "$tmp_nets" "$tmp_nets"

    # 2. Inject all resolved IPs & CIDRs into nftables set 'zapret'
    local added_count=0
    touch "$AUTO_CIDR_LIST"
    while read -r target; do
        [ -n "$target" ] || continue
        nft add element inet zapret2 zapret { "$target" } 2>/dev/null || true
        if ! grep -q "^$target$" "$AUTO_CIDR_LIST" 2>/dev/null; then
            echo "$target" >> "$AUTO_CIDR_LIST"
            added_count=$(( added_count + 1 ))
        fi
    done < "$tmp_nets"

    log "Добавлено в nftables zapret (TCP/UDP): $added_count подсетей/IP для $domain"

    # Ensure domain is in zapret-hosts-auto.txt
    if ! grep -q "^$domain$" "$AUTOHOSTS" 2>/dev/null; then
        echo "$domain" >> "$AUTOHOSTS"
    fi

    # 3. Test TCP reachability (check if IP is completely blacklisted/BGP-dropped)
    local first_ip
    first_ip=$(head -n 1 "$tmp_ips")
    local tcp_syn_ok=0
    
    # Quick probe: test TCP connection with 2 second timeout
    if curl -s -m 2 -o /dev/null "https://$first_ip" 2>/dev/null; then
        tcp_syn_ok=1
    else
        local err_code=$?
        # Code 35 (SSL error), 56, 92, 000 with handshake means TCP connected, DPI intervened (desync will handle it!)
        # Code 28 (Connection timed out) means TCP SYN is dropped upstream (IP ban!)
        if [ "$err_code" != "28" ] && [ "$err_code" != "7" ]; then
            tcp_syn_ok=1
        fi
    fi

    if [ "$tcp_syn_ok" = "1" ]; then
        log "TCP рукопожатие успешно! Трафик $domain обрабатывается мульти-стратегией DPI (circular rotation)"
    else
        log "ВНИМАНИЕ: $domain ($first_ip) не отвечает на TCP SYN (вероятен бан по IP). Маршрутизация в WARP..."
        if [ -x "$WARP_SH" ]; then
            while read -r target; do
                [ -n "$target" ] || continue
                # Route specific IPs / subnets into Cloudflare WARP
                if echo "$target" | grep -q '/'; then
                    $WARP_SH add_target "$target" 2>/dev/null || true
                else
                    $WARP_SH add_target "$target/32" 2>/dev/null || true
                fi
            done < "$tmp_nets"
            log "Все подсети $domain направлены в туннель Cloudflare WARP"
        fi
    fi

    rm -f "$tmp_ips" "$tmp_nets"
    return 0
}

# Continuous daemon loop monitoring failing connections
run_daemon() {
    # Ensure lock
    if [ -f "$LOCKFILE" ]; then
        PID=$(cat "$LOCKFILE")
        if kill -0 "$PID" 2>/dev/null; then
            echo "Daemon already running with PID $PID"
            exit 0
        fi
    fi
    echo $$ > "$LOCKFILE"
    trap "rm -f $LOCKFILE; exit 0" INT TERM EXIT

    log "Демон автоматического определения доменов и IPCIDR запущен (PID: $$)"

    SEEN_FILE="/tmp/zapret2_autolearn_seen.txt"
    touch "$SEEN_FILE"

    while true; do
        # 1. Tail debug log for instant triggers (real-time fail detection)
        if [ -s "$AUTOHOSTS_DEBUG" ]; then
            # Format: 'DD.MM.YYYY HH:MM:SS : <domain> : profile ... : adding to ...'
            local ddom
            ddom=$(tail -n 5 "$AUTOHOSTS_DEBUG" | awk -F ' : ' '/adding to/ {print $2}' | tr -d ' ' | tail -n 1)
            if [ -n "$ddom" ] && ! grep -q "^$ddom$" "$SEEN_FILE" 2>/dev/null; then
                echo "$ddom" >> "$SEEN_FILE"
                resolve_and_learn "$ddom"
            fi
        fi

        # 2. Check zapret-hosts-auto.txt for any newly added domains
        if [ -s "$AUTOHOSTS" ]; then
            while read -r dom; do
                [ -n "$dom" ] || continue
                echo "$dom" | grep -q '^#' && continue
                dom=$(echo "$dom" | tr -d '\r\n ')
                
                if ! grep -q "^$dom$" "$SEEN_FILE" 2>/dev/null; then
                    echo "$dom" >> "$SEEN_FILE"
                    resolve_and_learn "$dom"
                fi
            done < "$AUTOHOSTS"
        fi

        # 3. Check conntrack for hard IP bans (TCP SYN_SENT [UNREPLIED])
        if [ -r /proc/net/nf_conntrack ]; then
            awk '
                /tcp/ && /SYN_SENT/ && /\[UNREPLIED\]/ {
                    for (i=1; i<=NF; i++) {
                        if ($i ~ /^dst=/) {
                            sub(/^dst=/, "", $i)
                            if ($i !~ /^(192\.168\.|10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|127\.|255\.|0\.)/) {
                                print $i
                            }
                        }
                    }
                }
            ' /proc/net/nf_conntrack | sort -u | while read -r dead_ip; do
                [ -n "$dead_ip" ] || continue
                if grep -q "^$dead_ip$" "$SEEN_FILE" 2>/dev/null; then
                    continue
                fi
                echo "$dead_ip" >> "$SEEN_FILE"

                # Verify if WAN TCP SYN times out (hard IP block)
                if ! nc -w 1 "$dead_ip" 443 </dev/null >/dev/null 2>&1; then
                    log "Обнаружен сбой TCP SYN к IP $dead_ip (вероятен IP бан). Автоматическое перенаправление в WARP..."
                    if [ -x /opt/zapret2/warp.sh ]; then
                        /opt/zapret2/warp.sh add_target "$dead_ip"
                    fi
                fi
            done
        fi

        sleep 2
    done
}

case "$1" in
    daemon)
        run_daemon
        ;;
    scan|add)
        shift
        resolve_and_learn "$1"
        ;;
    list)
        echo "=== Автоматически определенные домены и IPCIDR подсети ==="
        echo "--- Домены в autohostlist ---"
        cat "$AUTOHOSTS" 2>/dev/null || echo "(пусто)"
        echo ""
        echo "--- Агрегированные подсети (CIDR) в nftables ---"
        cat "$AUTO_CIDR_LIST" 2>/dev/null || echo "(пусто)"
        ;;
    *)
        echo "Использование: $0 {daemon|scan <domain>|list}"
        exit 1
        ;;
esac

