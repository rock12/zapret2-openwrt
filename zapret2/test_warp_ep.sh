#!/bin/sh
candidates="
162.159.192.1:2408
162.159.193.1:2408
162.159.195.1:2408
188.114.96.1:2408
188.114.97.1:2408
188.114.98.1:2408
188.114.99.1:2408
162.159.192.2:500
162.159.193.2:1701
162.159.195.2:4500
188.114.96.2:854
188.114.97.2:890
188.114.98.2:928
188.114.99.2:1074
162.159.192.3:2408
162.159.193.3:2408
162.159.195.3:2408
188.114.96.3:2408
188.114.97.3:2408
188.114.98.3:2408
188.114.99.3:2408
162.159.192.4:2408
162.159.193.4:2408
162.159.195.4:2408
188.114.96.4:2408
188.114.97.4:2408
188.114.98.4:2408
188.114.99.4:2408
162.159.192.5:2408
162.159.193.5:2408
162.159.195.5:2408
188.114.96.5:2408
188.114.97.5:2408
188.114.98.5:2408
188.114.99.5:2408
"

for ep in $candidates; do
    [ -n "$ep" ] || continue
    echo "Checking $ep..."
    wg set warp peer "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=" endpoint "$ep"
    sleep 1
    res=$(curl --interface warp -s -m 3 https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null)
    if [ -n "$res" ]; then
        loc=$(echo "$res" | awk -F= '$1=="loc" {print $2}')
        colo=$(echo "$res" | awk -F= '$1=="colo" {print $2}')
        echo "===> SUCCESS! $ep -> loc=$loc, colo=$colo"
        if [ "$loc" != "RU" ]; then
            echo "FOUND EUROPE ENDPOINT: $ep (loc=$loc, colo=$colo)"
            echo "$ep" > /tmp/found_eu_ep.txt
            break
        fi
    fi
done
