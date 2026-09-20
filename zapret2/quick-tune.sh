#!/bin/sh
# Quick-Tune Turbo DPI checker for specific domain or IP
# Tests top 6 high-efficiency desync patterns in ~3-5 seconds

DOMAIN="$1"
[ -n "$DOMAIN" ] || { echo "Usage: $0 <domain>"; exit 1; }

NFQWS2="/opt/zapret2/nfq2/nfqws2"
QNUM=389
CURL="curl -sI -k --connect-timeout 2 -m 3"

# Check prerequisites
[ -x "$NFQWS2" ] || { echo "nfqws2 not found"; exit 1; }

# Setup temporary nftables interception for test qnum
cleanup() {
    [ -n "$DAEMON_PID" ] && kill -9 "$DAEMON_PID" 2>/dev/null
    nft delete element inet zapret2 autotune_test_ips { "$TEST_IP" } 2>/dev/null || true
    nft delete rule inet zapret2 postrouting handle "$RULE_HANDLE" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# Resolve target domain
TEST_IP=$(nslookup "$DOMAIN" 127.0.0.1 2>/dev/null | awk '/^Address: / {print $2}' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)
[ -z "$TEST_IP" ] && TEST_IP=$(nslookup "$DOMAIN" 8.8.8.8 2>/dev/null | awk '/^Address: / {print $2}' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)

if [ -z "$TEST_IP" ]; then
    echo "ERROR: Failed to resolve domain $DOMAIN"
    exit 2
fi

# Patterns to test: id|description|nfqws_opt
PATTERNS="
1|multisplit_seqovl|--filter-tcp=443 --filter-l7=tls --payload=tls_client_hello --lua-desync=multisplit:pos=1,midsld:seqovl=1
2|fake_ts_multisplit|--filter-tcp=443 --filter-l7=tls --payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:tcp_ts=-1000:repeats=6 --lua-desync=multisplit:pos=1,midsld
3|fake_sni_google|--filter-tcp=443 --filter-l7=tls --payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:tcp_md5:repeats=11:tls_mod=rnd,dupsid,sni=www.google.com --lua-desync=multidisorder:pos=1,midsld
4|hostfakesplit_mailru|--filter-tcp=443 --filter-l7=tls --payload=tls_client_hello --lua-desync=hostfakesplit:host=mail.ru:tcp_ts=-600000:tcp_ts_up
5|fakedsplit_null|--filter-tcp=443 --filter-l7=tls --payload=tls_client_hello --lua-desync=fakedsplit:pattern=0x00:repeats=6:tcp_ts=-600000:tcp_ts_up
6|wssize_disorder|--filter-tcp=443 --filter-l7=tls --payload=tls_client_hello --lua-desync=wssize:wsize=1:scale=6 --lua-desync=multidisorder:pos=1,midsld
"

# Add direct nftables rule for test IP to bypass existing zapret queue and send to QNUM
nft insert rule inet zapret2 postnat ip daddr "$TEST_IP" tcp dport 443 queue flags bypass to $QNUM 2>/dev/null || true

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

    # Test HTTP response
    code=$($CURL "https://$DOMAIN" 2>/dev/null | head -n 1 | awk '{print $2}')
    if [ -n "$code" ] && [ "$code" -ge 200 ] && [ "$code" -lt 500 ]; then
        FOUND_ID="$pid"
        FOUND_NAME="$pdesc"
        FOUND_PATTERN="$popt"
        break
    fi
done

if [ -n "$FOUND_ID" ]; then
    echo "SUCCESS:$FOUND_ID:$FOUND_NAME:$FOUND_PATTERN"
    exit 0
else
    echo "FAILED: No strategy worked directly"
    exit 1
fi
