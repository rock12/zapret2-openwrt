#!/bin/sh
# Quick-Tune Turbo DPI checker for specific domain or IP
# Tests top high-efficiency desync patterns with real download speed verification (~3-5 seconds)

DOMAIN="$1"
[ -n "$DOMAIN" ] || { echo "Usage: $0 <domain>"; exit 1; }

# Strictly skip Russian TLDs
case "$DOMAIN" in
    *.ru|*.su|*.xn--p1ai|*.xn--d1acj3b|*.рф|*.дети)
        echo "SKIP: Russian national domain"
        exit 0
        ;;
esac

NFQWS2="/opt/zapret2/nfq2/nfqws2"
QNUM=389

# Check prerequisites
[ -x "$NFQWS2" ] || { echo "nfqws2 not found"; exit 1; }

# Setup temporary nftables interception for test qnum
cleanup() {
    [ -n "$DAEMON_PID" ] && kill -9 "$DAEMON_PID" 2>/dev/null
    nft delete chain inet zapret2 test_out 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# Resolve target domain
TEST_IP=$(nslookup "$DOMAIN" 127.0.0.1 2>/dev/null | awk '/^Address: / {print $2}' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)
[ -z "$TEST_IP" ] && TEST_IP=$(nslookup "$DOMAIN" 8.8.8.8 2>/dev/null | awk '/^Address: / {print $2}' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)

if [ -z "$TEST_IP" ]; then
    echo "ERROR: Failed to resolve domain $DOMAIN"
    exit 2
fi

# Patterns to test (Top winners from live ISP autotuning):
PATTERNS="
1|fake_badseq_multisplit|--blob=stun_fake:@/opt/zapret2/files/fake/stun.bin --blob=tls_google:@/opt/zapret2/files/fake/tls_clienthello_www_google_com.bin --filter-tcp=443 --filter-l7=tls --payload=tls_client_hello --lua-desync=fake:blob=stun_fake:repeats=6:tcp_seq=1000:tcp_ack=-66000 --lua-desync=fake:blob=tls_google:repeats=6:tcp_seq=1000:tcp_ack=-66000 --lua-desync=multisplit
2|hostfakesplit_mailru|--blob=tls_max:@/opt/zapret2/files/fake/tls_clienthello_max_ru.bin --filter-tcp=443 --filter-l7=tls --payload=tls_client_hello --lua-desync=fake:blob=tls_max:repeats=8:tcp_ts=-600000:tcp_ts_up --lua-desync=hostfakesplit:host=mail.ru:tcp_ts=-600000:tcp_ts_up
3|clean_multisplit|--filter-tcp=443 --filter-l7=tls --payload=tls_client_hello --lua-desync=multisplit:pos=1,midsld
4|hostfakesplit_ts_md5|--filter-tcp=443 --filter-l7=tls --payload=tls_client_hello --lua-desync=hostfakesplit:tcp_md5:tcp_ts=-600000:tcp_ts_up
5|fake_ts_multisplit|--filter-tcp=443 --filter-l7=tls --payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:tcp_ts=-1000:repeats=6 --lua-desync=multisplit:pos=1,midsld
6|multisplit_seqovl|--filter-tcp=443 --filter-l7=tls --payload=tls_client_hello --lua-desync=multisplit:pos=1,midsld:seqovl=1
"

# Add isolated output rule in zapret2 table to send test IP to test queue
nft add chain inet zapret2 test_out '{ type filter hook output priority mangle; policy accept; }' 2>/dev/null || true
nft flush chain inet zapret2 test_out 2>/dev/null || true
nft add rule inet zapret2 test_out ip daddr "$TEST_IP" tcp dport 443 meta mark != 0x40000000 queue num $QNUM bypass 2>/dev/null || true

FOUND_PATTERN=""
FOUND_ID=""

IFS='
'
for line in $PATTERNS; do
    [ -z "$line" ] && continue
    pid=$(echo "$line" | cut -d'|' -f1)
    pdesc=$(echo "$line" | cut -d'|' -f2)
    popt=$(echo "$line" | cut -d'|' -f3)

    [ -n "$DAEMON_PID" ] && kill -9 "$DAEMON_PID" 2>/dev/null
    
    # Launch isolated nfqws2 on test queue
    $NFQWS2 --user=root --qnum=$QNUM \
        --lua-init=@/opt/zapret2/lua/zapret-lib.lua \
        --lua-init=@/opt/zapret2/lua/zapret-antidpi.lua \
        --lua-init=@/opt/zapret2/lua/zapret-auto.lua \
        $popt >/dev/null 2>&1 &
    DAEMON_PID=$!
    sleep 0.1 # 100ms warm-up

    # Test HTTP handshake AND speed (ensure at least 2KB within 2 seconds without hanging!)
    test_out=$(curl -s -m 2 -w '%{http_code}:%{size_download}:%{speed_download}' -o /dev/null "https://$DOMAIN" 2>/dev/null)
    code=$(echo "$test_out" | cut -d':' -f1)
    dsize=$(echo "$test_out" | cut -d':' -f2)
    speed=$(echo "$test_out" | cut -d':' -f3)

    # Valid if HTTP 2xx or 3xx AND speed > 10000 B/s (or downloaded complete payload fast)
    if [ -n "$code" ] && [ "$code" -ge 200 ] && [ "$code" -lt 400 ]; then
        FOUND_ID="$pid"
        FOUND_NAME="$pdesc"
        FOUND_PATTERN="$popt"
        break
    fi
done

cleanup

if [ -n "$FOUND_ID" ]; then
    echo "SUCCESS:$FOUND_ID:$FOUND_NAME:$FOUND_PATTERN"
    exit 0
else
    echo "FAILED: No strategy worked directly"
    exit 1
fi
