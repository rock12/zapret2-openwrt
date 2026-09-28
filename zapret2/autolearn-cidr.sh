#!/bin/sh
# Dedicated Autolearn & IPCIDR Subnet Manager for zapret2
# Detects failed domains, resolves IPs, aggregates CIDR subnets,
# adds them to nftables (TCP & UDP), and routes IP-blocked targets to WARP.
# Strictly excludes Russian national domains (.ru, .su, .рф, .дети).

AUTOHOSTS="/opt/zapret2/ipset/zapret-hosts-auto.txt"
AUTOHOSTS_DEBUG="/opt/zapret2/ipset/zapret-hosts-auto-debug.log"
AUTO_CIDR_LIST="/opt/zapret2/ipset/zapret-hosts-auto-cidr.txt"
EXCLUDE_HOSTS="/opt/zapret2/ipset/zapret-hosts-user-exclude.txt"
EXCLUDE_IPS="/opt/zapret2/ipset/zapret-ip-user-exclude.txt"
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

is_excluded_domain() {
    local d="$1"
    [ -f "$EXCLUDE_HOSTS" ] || return 1
    local check="$d"
    while [ -n "$check" ]; do
        if grep -F -x -q "$check" "$EXCLUDE_HOSTS" 2>/dev/null; then
            return 0
        fi
        case "$check" in
            *.*) check="${check#*.}" ;;
            *) break ;;
        esac
    done
    return 1
}

sync_ip_excludes() {
    [ -f "$EXCLUDE_IPS" ] || return 0
    while read -r ex_ip; do
        ex_ip=$(echo "$ex_ip" | tr -d '\r\n ')
        [ -n "$ex_ip" ] || continue
        echo "$ex_ip" | grep -q '^#' && continue
        nft add element inet zapret2 nozapret { "$ex_ip" } 2>/dev/null || true
        nft delete element inet zapret2 zapret { "$ex_ip" } 2>/dev/null || true
    done < "$EXCLUDE_IPS"
}

# Resolve and determine all IP addresses and CIDR subnets for a domain
resolve_and_learn() {
    local domain="$1"
    [ -n "$domain" ] || return 0

    # Strip protocol or trailing slashes if passed as URL
    domain=$(echo "$domain" | sed -e 's|^[^/]*//||' -e 's|/.*$||' -e 's|:.*$||' | tr 'A-Z' 'a-z')

    # 1. Strictly skip Russian domains
    if is_russian_domain "$domain"; then
        log "Пропуск: Национальный домен РФ ($domain)"
        return 0
    fi

    # 2. Check if domain or parent domain is excluded
    if is_excluded_domain "$domain"; then
        log "Пропуск: $domain в списке исключений"
        # If it was erroneously added to auto hosts, remove it
        sed -i "/^$domain$/d" "$AUTOHOSTS" 2>/dev/null || true
        return 0
    fi

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

    local first_ip
    first_ip=$(head -n 1 "$tmp_ips")

    # Inject all resolved IPs & CIDRs into nftables set 'zapret'
    local added_count=0
    touch "$AUTO_CIDR_LIST"
    while read -r target; do
        [ -n "$target" ] || continue
        # Check if target IP/CIDR is in exclude list or nozapret set
        if [ -f "$EXCLUDE_IPS" ] && grep -F -x -q "$target" "$EXCLUDE_IPS" 2>/dev/null; then
            continue
        fi
        if nft list set inet zapret2 nozapret 2>/dev/null | grep -F -q "$target"; then
            continue
        fi

        nft add element inet zapret2 zapret { "$target" } 2>/dev/null || true
        if ! grep -q "^$target$" "$AUTO_CIDR_LIST" 2>/dev/null; then
            echo "$target" >> "$AUTO_CIDR_LIST"
            added_count=$(( added_count + 1 ))
        fi
    done < "$tmp_nets"

    log "Добавлено в nftables zapret (TCP/UDP): $added_count подсетей/IP для $domain"
    rm -f "$tmp_ips" "$tmp_nets"
    return 0
}

# Continuous daemon loop monitoring failing connections
run_daemon() {
    local ddom=""
    # Ensure lock
    if [ -f "$LOCKFILE" ]; then
        PID=$(cat "$LOCKFILE" 2>/dev/null)
        if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
            echo "Daemon already running with PID $PID"
            exit 0
        fi
    fi
    echo $$ > "$LOCKFILE"
    trap "rm -f '$LOCKFILE'; exit 0" INT TERM EXIT

    log "Демон автоматического определения доменов и IPCIDR запущен (PID: $$)"

    sync_ip_excludes
    SEEN_FILE="/tmp/zapret2_autolearn_seen.txt"
    touch "$SEEN_FILE"

    while true; do
        # 1. Tail debug log for instant triggers (real-time fail detection)
        if [ -s "$AUTOHOSTS_DEBUG" ]; then
            # Format: 'DD.MM.YYYY HH:MM:SS : <domain> : profile ... : adding to ...'
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

        sleep 5
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

