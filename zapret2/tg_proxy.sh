#!/bin/sh
# TG WS Proxy Manager for OpenWrt (Zapret2 integration)
# (c) 2026 Zapret2 OpenWrt Project

BIN_PATH="/usr/bin/tg-ws-proxy-go"
INIT_PATH="/etc/init.d/tg-ws-proxy-go"
VERSION="1.4.1"
PORT=2080

get_lan_ip() {
    local ip
    ip=$(uci -q get network.lan.ipaddr)
    [ -z "$ip" ] && ip=$(ip -4 addr show br-lan 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -n1)
    [ -z "$ip" ] && ip="192.168.1.1"
    ip=${ip%%/*}
    echo "$ip"
}

get_arch_bin() {
    local arch
    arch=$(uname -m)
    case "$arch" in
        aarch64*)
            echo "tg-ws-proxy-openwrt-aarch64"
            ;;
        armv7*|armv8*|arm*)
            echo "tg-ws-proxy-openwrt-armv7"
            ;;
        x86_64*)
            echo "tg-ws-proxy-openwrt-x86_64"
            ;;
        mips*el*)
            echo "tg-ws-proxy-openwrt-mipsel_24kc"
            ;;
        mips*)
            echo "tg-ws-proxy-openwrt-mips_24kc"
            ;;
        *)
            echo ""
            ;;
    esac
}

cmd_status() {
    local installed=0
    local running=0
    local pid=""
    local lan_ip
    lan_ip=$(get_lan_ip)

    if [ -x "$BIN_PATH" ]; then
        installed=1
    fi

    pid=$(pidof tg-ws-proxy-go 2>/dev/null)
    if [ -n "$pid" ]; then
        running=1
    fi

    printf '{"installed":%d,"running":%d,"pid":"%s","port":%d,"lan_ip":"%s","link":"tg://socks?server=%s&port=%d"}\n' \
        "$installed" "$running" "$pid" "$PORT" "$lan_ip" "$lan_ip" "$PORT"
}

cmd_install() {
    local bin_name
    bin_name=$(get_arch_bin)
    if [ -z "$bin_name" ]; then
        echo "Error: unsupported architecture $(uname -m)" >&2
        return 1
    fi

    local url="https://github.com/d0mhate/-tg-ws-proxy-Manager-go/releases/download/v${VERSION}/${bin_name}"
    echo "Downloading TG WS Proxy from $url..."
    curl -fsSL -o "$BIN_PATH" "$url" || {
        echo "Download failed!" >&2
        rm -f "$BIN_PATH"
        return 1
    }
    chmod +x "$BIN_PATH"

    cat << 'EOF' > "$INIT_PATH"
#!/bin/sh /etc/rc.common
START=99
USE_PROCD=1

start_service() {
    procd_open_instance
    procd_set_param command /usr/bin/tg-ws-proxy-go --host 0.0.0.0 --port 2080 --cf-proxy --cf-proxy-first --cf-balance
    procd_set_param respawn
    procd_close_instance
}
EOF
    chmod +x "$INIT_PATH"
    "$INIT_PATH" enable
    "$INIT_PATH" restart
    sleep 1
    cmd_status
}

cmd_remove() {
    if [ -f "$INIT_PATH" ]; then
        "$INIT_PATH" stop 2>/dev/null || true
        "$INIT_PATH" disable 2>/dev/null || true
        rm -f "$INIT_PATH"
    fi
    killall tg-ws-proxy-go 2>/dev/null || true
    rm -f "$BIN_PATH"
    cmd_status
}

cmd_start() {
    [ -x "$INIT_PATH" ] && "$INIT_PATH" start
    sleep 1
    cmd_status
}

cmd_stop() {
    [ -x "$INIT_PATH" ] && "$INIT_PATH" stop
    sleep 1
    cmd_status
}

cmd_restart() {
    [ -x "$INIT_PATH" ] && "$INIT_PATH" restart
    sleep 1
    cmd_status
}

case "$1" in
    status)
        cmd_status
        ;;
    install)
        cmd_install
        ;;
    remove)
        cmd_remove
        ;;
    start)
        cmd_start
        ;;
    stop)
        cmd_stop
        ;;
    restart)
        cmd_restart
        ;;
    *)
        echo "Usage: $0 {status|install|remove|start|stop|restart}" >&2
        exit 1
        ;;
esac
