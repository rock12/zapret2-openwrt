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
    [ "$FINISHED_CLEANLY" = "1" ] && return
    log "Очистка тестового окружения..."
    [ -n "$ENGINE_PID" ] && kill "$ENGINE_PID" 2>/dev/null || true
    nft delete table inet "$NFT_TABLE" 2>/dev/null || true
    rm -f "$PID_FILE"
    if [ "$WAS_RUNNING" = "1" ]; then
        log "Восстановление службы Zapret2..."
        /etc/init.d/zapret2 start 2>/dev/null || true
    fi
}

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
    local out_f="$3"
    if [ -z "$ip" ]; then
        if [ -n "$out_f" ]; then echo "0:0" > "$out_f"; else echo "0:0"; fi
        return
    fi
    local t_start="$(date +%s%3N 2>/dev/null || date +%s)"
    local code="$(curl -I -k --silent --output /dev/null --write-out '%{http_code}' --connect-timeout 2 --max-time 3 --resolve "$host:443:$ip" "https://$host/" 2>/dev/null)"
    local t_end="$(date +%s%3N 2>/dev/null || date +%s)"
    local diff=$(( t_end - t_start ))
    [ "$diff" -le 0 ] && diff=1
    local res="0:$diff"
    case "$code" in
        200|204|206|301|302|303|307|308)
            res="1:$diff"
            ;;
    esac
    if [ -n "$out_f" ]; then
        echo "$res" > "$out_f"
    else
        echo "$res"
    fi
}

run_autotune() {
    local mode="${1:-auto}" # auto | test
    FINISHED_CLEANLY=0
    trap cleanup INT TERM EXIT
    echo $$ > "$PID_FILE"
    : > "$LOG_FILE"

    cat <<EOF > "$JSON_FILE"
{
  "running": true,
  "progress": 0,
  "current": "Инициализация тестирования...",
  "index": 0,
  "total": 25,
  "best": null
}
EOF

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
    IG_IP="$(resolve_ip www.instagram.com)"
    GH_IP="$(resolve_ip github.com)"
    X_IP="$(resolve_ip x.com)"

    log "YouTube:     www.youtube.com   -> ${YT_IP:-НЕ ОПРЕДЕЛЕН}"
    log "Discord:     discord.com       -> ${DC_IP:-НЕ ОПРЕДЕЛЕН}"
    log "Rutracker:   rutracker.org     -> ${RT_IP:-НЕ ОПРЕДЕЛЕН}"
    log "Instagram:   www.instagram.com -> ${IG_IP:-НЕ ОПРЕДЕЛЕН}"
    log "GitHub:      github.com        -> ${GH_IP:-НЕ ОПРЕДЕЛЕН}"
    log "X (Twitter): x.com            -> ${X_IP:-НЕ ОПРЕДЕЛЕН}"

    if [ -z "$YT_IP" ] && [ -z "$DC_IP" ] && [ -z "$GH_IP" ]; then
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
    [ -n "$IG_IP" ] && nft add rule inet "$NFT_TABLE" out meta mark != "$TEST_MARK" ip daddr "$IG_IP" tcp dport 443 queue num "$TEST_QNUM" bypass
    [ -n "$GH_IP" ] && nft add rule inet "$NFT_TABLE" out meta mark != "$TEST_MARK" ip daddr "$GH_IP" tcp dport 443 queue num "$TEST_QNUM" bypass
    [ -n "$X_IP" ] && nft add rule inet "$NFT_TABLE" out meta mark != "$TEST_MARK" ip daddr "$X_IP" tcp dport 443 queue num "$TEST_QNUM" bypass

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
zm_alt|Zapret-Manager ALT (Fake + Fakedsplit ts)|--blob=stun_fake:@/opt/zapret2/files/fake/stun.bin --blob=tls_google:@/opt/zapret2/files/fake/tls_clienthello_www_google_com.bin --filter-tcp=443 --filter-l7=tls --payload=tls_client_hello --lua-desync=fake:blob=stun_fake:repeats=6:tcp_ts=-600000:tcp_ts_up --lua-desync=fake:blob=tls_google:repeats=6:tcp_ts=-600000:tcp_ts_up --lua-desync=fakedsplit:pattern=0x00:repeats=6:tcp_ts=-600000:tcp_ts_up
zm_alt2|Zapret-Manager ALT2 (Multisplit seqovl=652 pos=2)|--blob=tls_google:@/opt/zapret2/files/fake/tls_clienthello_www_google_com.bin --filter-tcp=443 --filter-l7=tls --payload=tls_client_hello --lua-desync=multisplit:pos=2:seqovl=652:seqovl_pattern=tls_google
zm_alt3|Zapret-Manager ALT3 (Fake ya.ru + Hostfakesplit ts)|--filter-tcp=443 --filter-l7=tls --payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:tls_mod=rnd,dupsid,sni=ya.ru:tcp_ts=-600000:tcp_ts_up --lua-desync=hostfakesplit:host=ya.ru:tcp_ts=-600000:tcp_ts_up
zm_alt4|Zapret-Manager ALT4 (Fake badseq 1000 + Multisplit)|--blob=stun_fake:@/opt/zapret2/files/fake/stun.bin --blob=tls_google:@/opt/zapret2/files/fake/tls_clienthello_www_google_com.bin --filter-tcp=443 --filter-l7=tls --payload=tls_client_hello --lua-desync=fake:blob=stun_fake:repeats=6:tcp_seq=1000:tcp_ack=-66000:tcp_ts_up --lua-desync=fake:blob=tls_google:repeats=6:tcp_seq=1000:tcp_ack=-66000:tcp_ts_up --lua-desync=multisplit
zm_alt5|Zapret-Manager ALT5 (Syndata + Multidisorder)|--filter-l3=ipv4 --filter-tcp=443 --filter-l7=tls --payload=tls_client_hello --lua-desync=syndata --lua-desync=multidisorder
zm_alt6|Zapret-Manager ALT6 (Multisplit seqovl=681 pos=1)|--blob=tls_google:@/opt/zapret2/files/fake/tls_clienthello_www_google_com.bin --filter-tcp=443 --filter-l7=tls --payload=tls_client_hello --lua-desync=multisplit:pos=1:seqovl=681:seqovl_pattern=tls_google
zm_alt7|Zapret-Manager ALT7 (Multisplit pos=2,sniext+1 seqovl=679)|--blob=tls_google:@/opt/zapret2/files/fake/tls_clienthello_www_google_com.bin --filter-tcp=443 --filter-l7=tls --payload=tls_client_hello --lua-desync=multisplit:pos=2,sniext+1:seqovl=679:seqovl_pattern=tls_google
zm_alt8|Zapret-Manager ALT8 (Fake badseq +2)|--filter-tcp=443 --filter-l7=tls --payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:repeats=6:tcp_seq=2:tcp_ack=-66000:tcp_ts_up
zm_alt9|Zapret-Manager ALT9 (Hostfakesplit ts+md5sig)|--filter-tcp=443 --filter-l7=tls --payload=tls_client_hello --lua-desync=hostfakesplit:tcp_md5:tcp_ts=-600000:tcp_ts_up
zm_alt10|Zapret-Manager ALT10 (Fake 4pda ts)|--blob=tls_4pda:@/opt/zapret2/files/fake/tls_clienthello_4pda_to.bin --filter-tcp=443 --filter-l7=tls --payload=tls_client_hello --lua-desync=fake:blob=tls_4pda:repeats=6:tcp_ts=-600000:tcp_ts_up
zm_alt11|Zapret-Manager ALT11 (Fake stun2 + Multisplit seqovl=664)|--blob=stun_fake:@/opt/zapret2/files/fake/stun2.bin --blob=tls_max:@/opt/zapret2/files/fake/tls_clienthello_max_ru.bin --filter-tcp=443 --filter-l7=tls --payload=tls_client_hello --lua-desync=fake:blob=stun_fake:repeats=8:tcp_ts=-600000:tcp_ts_up --lua-desync=fake:blob=tls_max:repeats=8:tcp_ts=-600000:tcp_ts_up --lua-desync=multisplit:pos=1:seqovl=664:seqovl_pattern=tls_max
zm_alt12|Zapret-Manager ALT12 (ALT11 + Google Hostfakesplit)|--blob=stun_fake:@/opt/zapret2/files/fake/stun2.bin --blob=tls_max:@/opt/zapret2/files/fake/tls_clienthello_max_ru.bin --filter-tcp=443 --filter-l7=tls --payload=tls_client_hello --lua-desync=fake:blob=stun_fake:repeats=8:tcp_ts=-600000:tcp_ts_up --lua-desync=fake:blob=tls_max:repeats=8:tcp_ts=-600000:tcp_ts_up --lua-desync=multisplit:pos=1:seqovl=664:seqovl_pattern=tls_max
zm_alt13|Zapret-Manager ALT13 (Fake + Hostfakesplit mail.ru ts)|--blob=tls_max:@/opt/zapret2/files/fake/tls_clienthello_max_ru.bin --filter-tcp=443 --filter-l7=tls --payload=tls_client_hello --lua-desync=fake:blob=tls_max:repeats=8:tcp_ts=-600000:tcp_ts_up --lua-desync=hostfakesplit:host=mail.ru:tcp_ts=-600000:tcp_ts_up
zm_exp|Zapret-Manager EXP (Fake + Multisplit seqovl=480 stun2)|--blob=stun_fake:@/opt/zapret2/files/fake/stun2.bin --blob=tls_google:@/opt/zapret2/files/fake/tls_clienthello_www_google_com.bin --filter-tcp=443 --filter-l7=tls --payload=tls_client_hello --lua-desync=fake:blob=tls_google:repeats=6:tcp_ts=-600000:tcp_ts_up --lua-desync=multisplit:pos=1:seqovl=480:seqovl_pattern=stun_fake
zm_fake_tls_auto|Zapret-Manager FAKE TLS AUTO (Fake + Multidisorder 1,midsld)|--filter-tcp=443 --filter-l7=tls --payload=tls_client_hello --lua-desync=fake:blob=0x00000000:repeats=11:tcp_seq=-10000:tcp_ack=-66000:tcp_ts_up --lua-desync=fake:blob=fake_default_tls:tls_mod=rnd,dupsid,sni=www.google.com:repeats=11:tcp_seq=-10000:tcp_ack=-66000:tcp_ts_up --lua-desync=multidisorder:pos=1,midsld
zm_fake_tls_auto_alt|Zapret-Manager FAKE TLS AUTO ALT (Fake + Fakedsplit pos=1)|--filter-tcp=443 --filter-l7=tls --payload=tls_client_hello --lua-desync=fake:blob=0x00000000:repeats=11:tcp_seq=-10000:tcp_ack=-66000:tcp_ts_up --lua-desync=fake:blob=fake_default_tls:tls_mod=rnd,dupsid,sni=www.google.com:repeats=11:tcp_seq=-10000:tcp_ack=-66000:tcp_ts_up --lua-desync=fakedsplit:pos=1
zm_fake_tls_auto_alt2|Zapret-Manager FAKE TLS AUTO ALT2 (Fake + Multisplit badseq)|--filter-tcp=443 --filter-l7=tls --payload=tls_client_hello --lua-desync=fake:blob=0x00000000:repeats=11:tcp_seq=-10000:tcp_ack=-66000:tcp_ts_up --lua-desync=fake:blob=fake_default_tls:tls_mod=rnd,dupsid,sni=www.google.com:repeats=11:tcp_seq=10000000:tcp_ack=-66000:tcp_ts_up --lua-desync=multisplit
zm_simple_fake|Zapret-Manager SIMPLE FAKE (Fake Google + ts)|--filter-tcp=443 --filter-l7=tls --payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:tls_mod=rnd,dupsid,sni=www.google.com:repeats=6:tcp_ts=-600000:tcp_ts_up
zm_simple_fake_alt|Zapret-Manager SIMPLE FAKE ALT (Fake badseq +2)|--filter-tcp=443 --filter-l7=tls --payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:repeats=6:tcp_seq=2:tcp_ack=-66000:tcp_ts_up
zm_martin_backer|Zapret-Manager MartinBacker (Circular Multi-strategy)|--blob=tls_clienthello:@/opt/zapret2/files/fake/tls_clienthello.bin --filter-tcp=443 --filter-l7=tls --payload=tls_client_hello --in-range=-s5556 --lua-desync=circular:fails=2:time=300:retrans=3:nld=2 --in-range=x --lua-desync=fake:blob=tls_clienthello:tls_mod=rnd,dupsid,sni=fonts.google.com:tcp_seq=10000:strategy=1 --lua-desync=multisplit:pos=1,midsld:seqovl=1:seqovl_pattern=tls_clienthello:tcp_ts_up:strategy=1 --lua-desync=fake:blob=0x00000000:tcp_ack=-66000:tls_mod=rnd,dupsid,sni=www.google.com:repeats=2:strategy=2 --lua-desync=multisplit:pos=1,midsld:strategy=2
zm_krushaaa|Zapret-Manager Krushaaa (BurgerKing + Magnit + ts)|--blob=tls_burger:@/opt/zapret2/files/fake/tls_burgerkingrus_ru.bin --blob=stun2_fake:@/opt/zapret2/files/fake/stun2.bin --filter-tcp=443 --filter-l7=tls --payload=tls_client_hello --lua-desync=fake:blob=stun2_fake:repeats=4:tcp_ts=-600000:tcp_ts_up --lua-desync=fake:blob=tls_burger:repeats=4:tcp_ts=-600000:tcp_ts_up
zm_uvvi2|Zapret-Manager Uvvi2 (Targeted Voice + Circular)|--blob=tls_clienthello:@/opt/zapret2/files/fake/tls_clienthello.bin --filter-tcp=443 --filter-l7=tls --payload=tls_client_hello --lua-desync=circular:fails=2:time=300:retrans=3:nld=2 --lua-desync=fake:blob=tls_clienthello:tls_mod=rnd,dupsid,sni=fonts.google.com:tcp_seq=10000:strategy=1 --lua-desync=multisplit:pos=1,midsld:seqovl=1:seqovl_pattern=tls_clienthello:tcp_ts_up:strategy=1
z2_ready_05|Multisplit sequence overlap (HR #5 / Flowseal)|--filter-tcp=443 --filter-l7=tls --payload=tls_client_hello --lua-desync=multisplit:pos=1,midsld:seqovl=1
z2_ready_06|Multidisorder SNI split (HR #6)|--filter-tcp=443 --filter-l7=tls --payload=tls_client_hello --lua-desync=multidisorder:pos=1,sniext+1,host+1,midsld-2,midsld,midsld+2,endhost-1
z2_ready_03|Timestamp fake + multisplit (HR #3)|--filter-tcp=443 --filter-l7=tls --payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:tcp_ts=-1000:repeats=6 --lua-desync=multisplit:pos=1,midsld
"

    INDEX=0
    TOTAL=$(echo "$CANDIDATES" | grep -c '|')
    printf '%s\n' "$CANDIDATES" > /tmp/zapret2_autotune_cand.tmp
    while IFS='|' read -r c_id c_title c_args; do
        [ -n "$c_id" ] || continue
        INDEX=$(( INDEX + 1 ))
        pct=$(( INDEX * 100 / TOTAL ))
        cat <<EOF > "$JSON_FILE"
{
  "running": true,
  "progress": $pct,
  "current": "$c_title",
  "index": $INDEX,
  "total": $TOTAL,
  "best": null
}
EOF
        log "--------------------------------------------------------"
        log "[$INDEX/$TOTAL] Проверка: $c_title ($c_id)"

        $NFQWS2_BIN --user=daemon --qnum="$TEST_QNUM" --fwmark="$TEST_MARK" \
            "--lua-init=@$ZAPRET_BASE/lua/zapret-lib.lua" \
            "--lua-init=@$ZAPRET_BASE/lua/zapret-antidpi.lua" \
            "--lua-init=@$ZAPRET_BASE/lua/zapret-auto.lua" \
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

        check_target www.youtube.com "$YT_IP" /tmp/at_yt.tmp &
        check_target discord.com "$DC_IP" /tmp/at_dc.tmp &
        check_target www.instagram.com "$IG_IP" /tmp/at_ig.tmp &
        check_target x.com "$X_IP" /tmp/at_x.tmp &
        check_target github.com "$GH_IP" /tmp/at_gh.tmp &
        check_target rutracker.org "$RT_IP" /tmp/at_rt.tmp &
        wait

        yt_res="$(cat /tmp/at_yt.tmp 2>/dev/null)"; rm -f /tmp/at_yt.tmp
        yt_ok="${yt_res%%:*}"
        yt_lat="${yt_res##*:}"

        dc_res="$(cat /tmp/at_dc.tmp 2>/dev/null)"; rm -f /tmp/at_dc.tmp
        dc_ok="${dc_res%%:*}"
        dc_lat="${dc_res##*:}"

        ig_res="$(cat /tmp/at_ig.tmp 2>/dev/null)"; rm -f /tmp/at_ig.tmp
        ig_ok="${ig_res%%:*}"
        ig_lat="${ig_res##*:}"

        x_res="$(cat /tmp/at_x.tmp 2>/dev/null)"; rm -f /tmp/at_x.tmp
        x_ok="${x_res%%:*}"
        x_lat="${x_res##*:}"

        gh_res="$(cat /tmp/at_gh.tmp 2>/dev/null)"; rm -f /tmp/at_gh.tmp
        gh_ok="${gh_res%%:*}"
        gh_lat="${gh_res##*:}"

        rt_res="$(cat /tmp/at_rt.tmp 2>/dev/null)"; rm -f /tmp/at_rt.tmp
        rt_ok="${rt_res%%:*}"
        rt_lat="${rt_res##*:}"

        kill -9 "$ENGINE_PID" 2>/dev/null || true
        wait "$ENGINE_PID" 2>/dev/null || true
        ENGINE_PID=""

        # Баллы: YouTube (2) + Discord (2) + Instagram (2) + X (2) + GitHub (1) + Rutracker (1) = макс 10
        score=$(( ${yt_ok:-0} * 2 + ${dc_ok:-0} * 2 + ${ig_ok:-0} * 2 + ${x_ok:-0} * 2 + ${gh_ok:-0} + ${rt_ok:-0} ))
        tot_lat=$(( ${yt_lat:-0} + ${dc_lat:-0} + ${ig_lat:-0} + ${x_lat:-0} + ${gh_lat:-0} + ${rt_lat:-0} ))

        log "  YouTube:     $([ "$yt_ok" = "1" ] && echo "ДОСТУПЕН (${yt_lat}ms)" || echo "НЕДОСТУПЕН")"
        log "  Discord:     $([ "$dc_ok" = "1" ] && echo "ДОСТУПЕН (${dc_lat}ms)" || echo "НЕДОСТУПЕН")"
        log "  Instagram:   $([ "$ig_ok" = "1" ] && echo "ДОСТУПЕН (${ig_lat}ms)" || echo "НЕДОСТУПЕН")"
        log "  X (Twitter): $([ "$x_ok" = "1" ] && echo "ДОСТУПЕН (${x_lat}ms)" || echo "НЕДОСТУПЕН")"
        log "  GitHub:      $([ "$gh_ok" = "1" ] && echo "ДОСТУПЕН (${gh_lat}ms)" || echo "НЕДОСТУПЕН")"
        log "  Rutracker:   $([ "$rt_ok" = "1" ] && echo "ДОСТУПЕН (${rt_lat}ms)" || echo "НЕДОСТУПЕН")"
        log "  Итоговый балл: $score/10 (Суммарный пинг: ${tot_lat}ms)"

        echo "$c_id|$c_title|$score|$tot_lat" >> "/tmp/zapret2_autotune_res.tmp"
    done < /tmp/zapret2_autotune_cand.tmp
    rm -f /tmp/zapret2_autotune_cand.tmp

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
            log "Идентификатор: $WIN_ID | Баллы: $WIN_SCORE/10 | Пинг: ${WIN_LAT}ms"
            log "========================================================"

            cat <<EOF > "$JSON_FILE"
{
  "running": false,
  "progress": 100,
  "best": {
    "id": "$WIN_ID",
    "title": "$WIN_TITLE",
    "score": $WIN_SCORE,
    "max_score": 10,
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
    start)
        smode="${2:-test}"
        if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE" 2>/dev/null)" 2>/dev/null; then
            echo "ALREADY_RUNNING"
            exit 0
        fi
        : > "$LOG_FILE"
        cat <<EOF > "$JSON_FILE"
{
  "running": true,
  "progress": 0,
  "current": "Запуск фонового подбора...",
  "index": 0,
  "total": 21,
  "best": null
}
EOF
        ( "$0" "$smode" ) </dev/null >/dev/null 2>&1 &
        echo "STARTED"
        ;;
    apply)
        strat_to_apply="$2"
        if [ -z "$strat_to_apply" ] && [ -f "$JSON_FILE" ]; then
            strat_to_apply="$(grep -o '"id": "[^"]*"' "$JSON_FILE" | head -n 1 | cut -d'"' -f4)"
        fi
        if [ -n "$strat_to_apply" ]; then
            log "Применение стратегии '$strat_to_apply'..."
            $ZAPRET_BASE/restore-def-cfg.sh "(skip_base)(sync)" "$strat_to_apply"
            /etc/init.d/zapret2 restart
            echo "APPLIED $strat_to_apply"
        else
            echo "NO_STRATEGY"
            exit 1
        fi
        ;;
    stop)
        cleanup
        exit 0
        ;;
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
        echo "Использование: $0 {start [auto|test]|apply [id]|stop|auto|test|status|log}"
        exit 1
        ;;
esac
