#!/bin/sh
# Zapret2 Auto-Tuning Engine for OpenWrt
# Based on Hellington-Rey/sing-box-service-check strategy catalog & testing worker
# (c) 2026

EXE_DIR="$(cd "$(dirname "$0")" 2>/dev/null || exit 1; pwd)"
ZAPRET_BASE="${ZAPRET_BASE:-$EXE_DIR}"
LOG_FILE="/tmp/zapret2_autotune.log"
JSON_FILE="/tmp/zapret2_autotune.json"
PID_FILE="/tmp/zapret2_autotune.pid"
NFT_TABLE="zapret2_autotune"
TEST_QNUM=300
TEST_MARK="0x40000000"

NFQWS2_BIN="$ZAPRET_BASE/nfq2/nfqws2"
[ -x "$NFQWS2_BIN" ] || NFQWS2_BIN="/opt/zapret2/nfq2/nfqws2"
[ -x "$NFQWS2_BIN" ] || NFQWS2_BIN="/usr/bin/nfqws2"

WAS_RUNNING=0
if /etc/init.d/zapret2 status 2>/dev/null | grep -q "running"; then
    WAS_RUNNING=1
fi

log() {
    local msg="[$(date '+%H:%M:%S')] $*"
    echo "$msg"
    echo "$msg" >> "$LOG_FILE"
}

cleanup() {
    log "Очистка тестового окружения..."
    [ -n "$ENGINE_PID" ] && kill "$ENGINE_PID" 2>/dev/null || true
    nft delete table inet "$NFT_TABLE" 2>/dev/null || true
    rm -f "$PID_FILE"
    if [ "$FINISHED_CLEANLY" != "1" ] && [ "$WAS_RUNNING" = "1" ]; then
        log "Восстановление службы Zapret2..."
        /etc/init.d/zapret2 start 2>/dev/null || true
    fi
}

trap cleanup INT TERM EXIT

resolve_ip() {
    local host="$1"
    local ip=""
    if command -v resolveip >/dev/null 2>&1; then
        ip="$(resolveip -4 "$host" 2>/dev/null | head -n 1)"
    fi
    if [ -z "$ip" ] && command -v nslookup >/dev/null 2>&1; then
        ip="$(nslookup "$host" 2>/dev/null | awk '/^Address[ 0-9]*: / { print $NF }' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)"
    fi
    echo "$ip"
}

check_target() {
    local host="$1"
    local ip="$2"
    [ -z "$ip" ] && { echo "0:0"; return; }
    local t_start="$(date +%s%3N 2>/dev/null || date +%s)"
    local code="$(curl -I -k --silent --output /dev/null --write-out '%{http_code}' --connect-timeout 4 --max-time 6 --resolve "$host:443:$ip" "https://$host/" 2>/dev/null)"
    local t_end="$(date +%s%3N 2>/dev/null || date +%s)"
    local diff=$(( t_end - t_start ))
    [ "$diff" -le 0 ] && diff=1
    case "$code" in
        200|204|206|301|302|303|307|308)
            echo "1:$diff"
            ;;
        *)
            echo "0:$diff"
            ;;
    esac
}

run_autotune() {
    local mode="${1:-auto}" # auto | test
    FINISHED_CLEANLY=0
    echo $$ > "$PID_FILE"
    : > "$LOG_FILE"

    log "=== Запуск автоподбора стратегий Zapret2 ==="
    log "Режим: $mode"

    if [ ! -x "$NFQWS2_BIN" ]; then
        log "Ошибка: Движок nfqws2 не найден: $NFQWS2_BIN"
        exit 1
    fi

    log "Разрешение IP-адресов целевых сервисов..."
    YT_IP="$(resolve_ip www.youtube.com)"
    DC_IP="$(resolve_ip discord.com)"
    RT_IP="$(resolve_ip rutracker.org)"

    log "YouTube:    www.youtube.com -> ${YT_IP:-НЕ ОПРЕДЕЛЕН}"
    log "Discord:    discord.com     -> ${DC_IP:-НЕ ОПРЕДЕЛЕН}"
    log "Rutracker:  rutracker.org   -> ${RT_IP:-НЕ ОПРЕДЕЛЕН}"

    if [ -z "$YT_IP" ] && [ -z "$DC_IP" ]; then
        log "Ошибка: Не удалось разрешить DNS для тестовых целей. Проверьте сеть или DoH (https-dns-proxy)."
        exit 1
    fi

    # Временно останавливаем основной сервис для захвата очереди netfilter
    if [ "$WAS_RUNNING" = "1" ]; then
        log "Временная приостановка основного сервиса Zapret2 для тестирования..."
        /etc/init.d/zapret2 stop >/dev/null 2>&1 || true
        killall -9 nfqws2 >/dev/null 2>&1 || true
        sleep 1
    fi

    # Изолированная таблица nftables для тестовых целей
    nft delete table inet "$NFT_TABLE" 2>/dev/null || true
    nft add table inet "$NFT_TABLE" || { log "Ошибка создания nftable $NFT_TABLE"; exit 1; }
    nft add chain inet "$NFT_TABLE" out '{ type filter hook output priority mangle; policy accept; }' || exit 1
    [ -n "$YT_IP" ] && nft add rule inet "$NFT_TABLE" out meta mark != "$TEST_MARK" ip daddr "$YT_IP" tcp dport 443 queue num "$TEST_QNUM" bypass
    [ -n "$DC_IP" ] && nft add rule inet "$NFT_TABLE" out meta mark != "$TEST_MARK" ip daddr "$DC_IP" tcp dport 443 queue num "$TEST_QNUM" bypass
    [ -n "$RT_IP" ] && nft add rule inet "$NFT_TABLE" out meta mark != "$TEST_MARK" ip daddr "$RT_IP" tcp dport 443 queue num "$TEST_QNUM" bypass

    cat <<EOF > "$JSON_FILE"
{
  "running": true,
  "progress": 0,
  "current": "",
  "best": null
}
EOF

    # Список кандидатов из каталога Hellington-Rey + Flowseal + Zapret-Manager
    CANDIDATES="
z2_ready_05|Multisplit sequence overlap (HR #5 / Flowseal)|--filter-tcp=443 --filter-l7=tls --payload=tls_client_hello --lua-desync=multisplit:pos=1,midsld:seqovl=1
zm_yv01|Zapret-Manager Yv01 (Google TLS Fake + Multisplit seqovl=681)|--filter-tcp=443 --filter-l7=tls --payload=tls_client_hello --ip-id=zero --lua-desync=multisplit:pos=1:seqovl=681:seqovl_pattern=blob_tls_clienthello_www_google_com
zm_yv02|Zapret-Manager Yv02 (Multisplit pos=1,sniext+1 seqovl=1)|--filter-tcp=443 --filter-l7=tls --payload=tls_client_hello --lua-desync=multisplit:pos=1,sniext+1:seqovl=1
zm_yv08|Zapret-Manager Yv08 (Hostfakesplit google.com tcp_ts=-600000)|--filter-tcp=443 --filter-l7=tls --payload=tls_client_hello --lua-desync=hostfakesplit:host=google.com:tcp_ts=-600000
zm_yv24|Zapret-Manager Yv24 (STUN Fake badsum + Multisplit seqovl=654)|--filter-tcp=443 --filter-l7=tls --payload=tls_client_hello --lua-desync=fake:blob=blob_stun:tcp_seq=-10000:badsum:repeats=8 --lua-desync=multisplit:pos=1:seqovl=654:seqovl_pattern=blob_stun
z2_ready_06|Multidisorder SNI split (HR #6)|--filter-tcp=443 --filter-l7=tls --payload=tls_client_hello --lua-desync=multidisorder:pos=1,sniext+1,host+1,midsld-2,midsld,midsld+2,endhost-1
z2_ready_01|Default fake + disorder (HR #1)|--filter-tcp=443 --filter-l7=tls --payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:tcp_md5:tcp_seq=-10000 --lua-desync=multidisorder:pos=1,midsld
z2_ready_03|Timestamp fake + multisplit (HR #3)|--filter-tcp=443 --filter-l7=tls --payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:tcp_ts=-1000:repeats=6 --lua-desync=multisplit:pos=1,midsld
z2_ready_04|MD5 fake + multisplit (HR #4)|--filter-tcp=443 --filter-l7=tls --payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:tcp_md5:repeats=6 --lua-desync=multisplit:pos=2,midsld
z2_ready_08|Window size + disorder (HR #8)|--filter-tcp=443 --filter-l7=tls --payload=tls_client_hello --lua-desync=wssize:wsize=1:scale=6 --lua-desync=multidisorder:pos=1,midsld
z2_ready_09|Repeated fake + multisplit (HR #9)|--filter-tcp=443 --filter-l7=tls --payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:tcp_md5:repeats=11:tls_mod=rnd,dupsid --lua-desync=multisplit:pos=2,midsld
z2_ready_10|Repeated fake + multidisorder (HR #10)|--filter-tcp=443 --filter-l7=tls --payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:tcp_ts=-1000:repeats=6 --lua-desync=multidisorder:pos=midsld
flowseal_simple_fake|Flowseal Simple Fake|--filter-tcp=443 --filter-l7=tls --payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:tcp_ts=-1000:repeats=6
"

    INDEX=0
    TOTAL=13
    rm -f "/tmp/zapret2_autotune_res.tmp"

    echo "$CANDIDATES" | while IFS='|' read -r c_id c_title c_args; do
        [ -n "$c_id" ] || continue
        INDEX=$(( INDEX + 1 ))
        pct=$(( INDEX * 100 / TOTAL ))
        log "--------------------------------------------------------"
        log "[$INDEX/$TOTAL] Проверка: $c_title ($c_id)"

        $NFQWS2_BIN --user=daemon --qnum="$TEST_QNUM" --fwmark="$TEST_MARK" \
            "--lua-init=@$ZAPRET_BASE/lua/zapret-lib.lua" \
            "--lua-init=@$ZAPRET_BASE/lua/zapret-antidpi.lua" \
            $c_args >/tmp/zapret2_autotune_engine.log 2>&1 &
        ENGINE_PID=$!

        ready=0
        for i in 1 2 3 4 5 6; do
            if grep -q "setting copy_packet mode" /tmp/zapret2_autotune_engine.log 2>/dev/null; then
                ready=1
                break
            fi
            sleep 0.3
        done

        if [ "$ready" != "1" ] || ! kill -0 "$ENGINE_PID" 2>/dev/null; then
            log "  -> Ошибка запуска движка nfqws2 для стратегии $c_id"
            kill -9 "$ENGINE_PID" 2>/dev/null || true
            continue
        fi

        yt_res="$(check_target www.youtube.com "$YT_IP")"
        yt_ok="${yt_res%%:*}"
        yt_lat="${yt_res##*:}"

        dc_res="$(check_target discord.com "$DC_IP")"
        dc_ok="${dc_res%%:*}"
        dc_lat="${dc_res##*:}"

        rt_res="$(check_target rutracker.org "$RT_IP")"
        rt_ok="${rt_res%%:*}"
        rt_lat="${rt_res##*:}"

        kill -9 "$ENGINE_PID" 2>/dev/null || true
        wait "$ENGINE_PID" 2>/dev/null || true
        ENGINE_PID=""

        score=$(( yt_ok * 2 + dc_ok * 2 + rt_ok ))
        tot_lat=$(( yt_lat + dc_lat + rt_lat ))

        log "  YouTube:   $([ "$yt_ok" = "1" ] && echo "ДОСТУПЕН (${yt_lat}ms)" || echo "НЕДОСТУПЕН")"
        log "  Discord:   $([ "$dc_ok" = "1" ] && echo "ДОСТУПЕН (${dc_lat}ms)" || echo "НЕДОСТУПЕН")"
        log "  Rutracker: $([ "$rt_ok" = "1" ] && echo "ДОСТУПЕН (${rt_lat}ms)" || echo "НЕДОСТУПЕН")"
        log "  Итоговый балл: $score/5 (Пинг: ${tot_lat}ms)"

        echo "$c_id|$c_title|$score|$tot_lat|$yt_ok|$dc_ok|$rt_ok" >> "/tmp/zapret2_autotune_res.tmp"
    done

    # Удаляем тестовую nftables таблицу
    nft delete table inet "$NFT_TABLE" 2>/dev/null || true

    if [ -f "/tmp/zapret2_autotune_res.tmp" ]; then
        BEST_LINE="$(sort -t'|' -k3,3nr -k4,4n "/tmp/zapret2_autotune_res.tmp" | head -n 1)"
        rm -f "/tmp/zapret2_autotune_res.tmp"
        if [ -n "$BEST_LINE" ]; then
            WIN_ID="$(echo "$BEST_LINE" | cut -d'|' -f1)"
            WIN_TITLE="$(echo "$BEST_LINE" | cut -d'|' -f2)"
            WIN_SCORE="$(echo "$BEST_LINE" | cut -d'|' -f3)"
            WIN_LAT="$(echo "$BEST_LINE" | cut -d'|' -f4)"
            
            log "========================================================"
            log "🏆 ПОБЕДИТЕЛЬ АВТОПОДБОРА: $WIN_TITLE"
            log "Идентификатор: $WIN_ID | Баллы: $WIN_SCORE/5"
            log "========================================================"

            cat <<EOF > "$JSON_FILE"
{
  "running": false,
  "progress": 100,
  "best": {
    "id": "$WIN_ID",
    "title": "$WIN_TITLE",
    "score": $WIN_SCORE,
    "latency": $WIN_LAT
  }
}
EOF

            if [ "$mode" = "auto" ] && [ "$WIN_SCORE" -gt 0 ]; then
                log "Применение победившей стратегии '$WIN_ID' в Zapret2..."
                $ZAPRET_BASE/restore-def-cfg.sh "(skip_base)(sync)" "$WIN_ID"
                FINISHED_CLEANLY=1
                /etc/init.d/zapret2 restart
                log "Стратегия '$WIN_ID' успешно применена и служба перезапущена!"
                return 0
            fi
            FINISHED_CLEANLY=1
            [ "$WAS_RUNNING" = "1" ] && /etc/init.d/zapret2 start
            return 0
        fi
    fi

    log "Не удалось найти работающую стратегию среди кандидатов."
    cat <<EOF > "$JSON_FILE"
{
  "running": false,
  "progress": 100,
  "best": null
}
EOF
    FINISHED_CLEANLY=1
    [ "$WAS_RUNNING" = "1" ] && /etc/init.d/zapret2 start
    return 1
}

case "$1" in
    run|auto)
        run_autotune auto
        ;;
    test)
        run_autotune test
        ;;
    status)
        if [ -f "$JSON_FILE" ]; then
            cat "$JSON_FILE"
        else
            echo '{"running": false}'
        fi
        ;;
    log)
        [ -f "$LOG_FILE" ] && cat "$LOG_FILE" || echo "Лог пуст"
        ;;
    *)
        echo "Использование: $0 {auto|test|status|log}"
        exit 1
        ;;
esac
