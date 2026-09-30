#!/bin/sh
# ==============================================================================
# Автоматический установщик zapret2-openwrt + AmneziaWG Cloudflare WARP
# Поддерживает:
#   - OpenWrt 23.05 / 24.10 (opkg)
#   - OpenWrt 25.12+ / SNAPSHOT (apk)
# Архитектуры: aarch64, armv7, x86_64, mips, mipsel, etc.
# Репозиторий: https://github.com/rock12/zapret2-openwrt (ветка zap1)
# ==============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

REPO_RAW="https://raw.githubusercontent.com/rock12/zapret2-openwrt/zap1"
INSTALL_DIR="/opt/zapret2"

echo ""
echo -e "${CYAN}======================================================================${NC}"
echo -e "${BOLD}${CYAN}      Установка zapret2-openwrt + AmneziaWG Cloudflare WARP           ${NC}"
echo -e "${CYAN}======================================================================${NC}"
echo ""

# 1. Проверка прав суперпользователя
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}[ОШИБКА] Скрипт должен быть запущен с правами root!${NC}"
    exit 1
fi

# 2. Определение пакетного менеджера (apk vs opkg)
echo -e "${YELLOW}[1/7] Проверка пакетного менеджера OpenWrt...${NC}"
PKG_MGR="none"
if command -v apk >/dev/null 2>&1; then
    PKG_MGR="apk"
    echo -e "      ${GREEN}✓${NC} Обнаружен менеджер пакетов ${BOLD}APK${NC} (OpenWrt >= 25.12+)"
elif command -v opkg >/dev/null 2>&1; then
    PKG_MGR="opkg"
    echo -e "      ${GREEN}✓${NC} Обнаружен менеджер пакетов ${BOLD}OPKG${NC} (OpenWrt <= 24.10)"
else
    echo -e "${RED}[ОШИБКА] Не найден пакетный менеджер (apk или opkg)!${NC}"
    exit 1
fi

# 3. Установка обязательных системных зависимостей
echo -e "\n${YELLOW}[2/7] Установка системных зависимостей...${NC}"
if [ "$PKG_MGR" = "apk" ]; then
    echo "      Обновление индексов пакетов (apk update)..."
    apk update || true
    
    # Если установлен forkop, убираем искусственный конфликт !https-dns-proxy
    if [ -f /lib/apk/db/installed ]; then
        sed -i 's/ !https-dns-proxy//g' /lib/apk/db/installed 2>/dev/null || true
    fi

    REQUIRED_PKGS="curl ca-bundle ca-certificates nftables kmod-nft-core kmod-nft-nat kmod-nft-queue kmod-nf-conntrack ip-full bind-tools dos2unix https-dns-proxy luci-app-https-dns-proxy"
    AMNEZIA_PKGS="kmod-amneziawg amneziawg-tools luci-proto-amneziawg"
    
    for p in $REQUIRED_PKGS; do
        if apk info -e "$p" >/dev/null 2>&1; then
            echo -e "      ${GREEN}✓${NC} $p (уже установлен)"
        else
            echo "      -> Установка $p..."
            apk add "$p" || echo -e "      ${YELLOW}[!] Не удалось установить $p (проверьте репозитории)${NC}"
        fi
    done

    # AmneziaWG packages
    for p in $AMNEZIA_PKGS; do
        if apk info -e "$p" >/dev/null 2>&1; then
            echo -e "      ${GREEN}✓${NC} $p (уже установлен)"
        else
            apk add "$p" 2>/dev/null || true
        fi
    done

    # Fallback на универсальный установщик AmneziaWG от Slava-Shchipunov если пакеты отсутствуют в стандартных репозиториях
    if ! command -v awg >/dev/null 2>&1 || ! lsmod | grep -q amneziawg; then
        echo "      -> Установка AmneziaWG через скрипт Slava-Shchipunov/awg-openwrt..."
        (curl -sSL --connect-timeout 15 https://raw.githubusercontent.com/Slava-Shchipunov/awg-openwrt/refs/heads/master/amneziawg-install.sh || wget -qO- https://raw.githubusercontent.com/Slava-Shchipunov/awg-openwrt/refs/heads/master/amneziawg-install.sh) | sh || true
    fi

    # Установка бинарного пакета zapret2 (nfqws2) и luci-app-zapret2 при их отсутствии
    ARCH=""
    [ -f /etc/openwrt_release ] && ARCH="$(. /etc/openwrt_release && echo "$DISTRIB_ARCH")"
    RELEASE_URL="https://github.com/rock12/zapret2-openwrt/releases/download/v1.0.5.1"
    if ! apk info -e zapret2 >/dev/null 2>&1 || [ ! -x /opt/zapret2/nfq2/nfqws2 ]; then
        if [ -n "$ARCH" ]; then
            echo "      -> Установка бинарного пакета zapret2 ($ARCH)..."
            curl -sSL -o /tmp/zapret2.apk "$RELEASE_URL/zapret2_${ARCH}.apk" 2>/dev/null || true
            [ -s /tmp/zapret2.apk ] && apk add --allow-untrusted /tmp/zapret2.apk 2>/dev/null || true
            rm -f /tmp/zapret2.apk
        fi
    fi
    if ! apk info -e luci-app-zapret2 >/dev/null 2>&1; then
        echo "      -> Установка пакета luci-app-zapret2..."
        curl -sSL -o /tmp/luci-app-zapret2.apk "$RELEASE_URL/luci-app-zapret2.apk" 2>/dev/null || true
        [ -s /tmp/luci-app-zapret2.apk ] && apk add --allow-untrusted /tmp/luci-app-zapret2.apk 2>/dev/null || true
        rm -f /tmp/luci-app-zapret2.apk
    fi
else
    echo "      Обновление индексов пакетов (opkg update)..."
    opkg update || true

    REQUIRED_PKGS="curl ca-bundle ca-certificates nftables kmod-nft-core kmod-nft-nat kmod-nft-queue kmod-nf-conntrack ip-full bind-tools dos2unix https-dns-proxy luci-app-https-dns-proxy"
    AMNEZIA_PKGS="kmod-amneziawg amneziawg-tools luci-proto-amneziawg"

    for p in $REQUIRED_PKGS; do
        if opkg list-installed | grep -qw "^$p"; then
            echo -e "      ${GREEN}✓${NC} $p (уже установлен)"
        else
            echo "      -> Установка $p..."
            opkg install "$p" || echo -e "      ${YELLOW}[!] Не удалось установить $p (проверьте репозитории)${NC}"
        fi
    done

    for p in $AMNEZIA_PKGS; do
        if ! opkg list-installed | grep -qw "^$p"; then
            opkg install "$p" 2>/dev/null || true
        fi
    done

    # Fallback на универсальный установщик AmneziaWG от Slava-Shchipunov если пакеты отсутствуют в стандартных репозиториях
    if ! command -v awg >/dev/null 2>&1 || ! lsmod | grep -q amneziawg; then
        echo "      -> Установка AmneziaWG через скрипт Slava-Shchipunov/awg-openwrt..."
        (curl -sSL --connect-timeout 15 https://raw.githubusercontent.com/Slava-Shchipunov/awg-openwrt/refs/heads/master/amneziawg-install.sh || wget -qO- https://raw.githubusercontent.com/Slava-Shchipunov/awg-openwrt/refs/heads/master/amneziawg-install.sh) | sh || true
    fi

    # Установка бинарного пакета zapret2 (nfqws2) и luci-app-zapret2 при их отсутствии
    ARCH=""
    [ -f /etc/openwrt_release ] && ARCH="$(. /etc/openwrt_release && echo "$DISTRIB_ARCH")"
    RELEASE_URL="https://github.com/rock12/zapret2-openwrt/releases/download/v1.0.5.1"
    if ! opkg list-installed | grep -qw "^zapret2" || [ ! -x /opt/zapret2/nfq2/nfqws2 ]; then
        if [ -n "$ARCH" ]; then
            echo "      -> Установка бинарного пакета zapret2 ($ARCH)..."
            curl -sSL -o /tmp/zapret2.ipk "$RELEASE_URL/zapret2_${ARCH}.ipk" 2>/dev/null || true
            [ -s /tmp/zapret2.ipk ] && opkg install /tmp/zapret2.ipk 2>/dev/null || true
            rm -f /tmp/zapret2.ipk
        fi
    fi
    if ! opkg list-installed | grep -qw "^luci-app-zapret2"; then
        echo "      -> Установка пакета luci-app-zapret2..."
        curl -sSL -o /tmp/luci-app-zapret2.ipk "$RELEASE_URL/luci-app-zapret2.ipk" 2>/dev/null || true
        [ -s /tmp/luci-app-zapret2.ipk ] && opkg install /tmp/luci-app-zapret2.ipk 2>/dev/null || true
        rm -f /tmp/luci-app-zapret2.ipk
    fi
fi

# 4. Подготовка каталогов
echo -e "\n${YELLOW}[3/7] Настройка каталогов и компонентов zapret2...${NC}"
mkdir -p "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR/warp"
mkdir -p "$INSTALL_DIR/warp/games"
mkdir -p "$INSTALL_DIR/ipset"
mkdir -p "$INSTALL_DIR/files/fake"
mkdir -p /etc/hotplug.d/iface

# Определение источника файлов: локальная папка (если скрипт запущен из клонированного репозитория) или скачивание из GitHub
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IS_LOCAL=0
if [ -f "$SCRIPT_DIR/zapret2/warp.sh" ] && [ -f "$SCRIPT_DIR/zapret2/init.d.sh" ]; then
    IS_LOCAL=1
fi

if [ "$IS_LOCAL" = "1" ]; then
    echo "      Копирование файлов из локального каталога..."
    cp -rf "$SCRIPT_DIR/zapret2/"* "$INSTALL_DIR/" 2>/dev/null || true
    cp -f "$SCRIPT_DIR/zapret2/init.d.sh" /etc/init.d/zapret2
    [ -f "$SCRIPT_DIR/uninstall.sh" ] && cp -f "$SCRIPT_DIR/uninstall.sh" "$INSTALL_DIR/uninstall.sh"
    
    if [ -d "$SCRIPT_DIR/luci-app-zapret2/htdocs" ]; then
        mkdir -p /www/luci-static/resources/view/zapret2
        cp -rf "$SCRIPT_DIR/luci-app-zapret2/htdocs/luci-static/resources/view/zapret2/"* /www/luci-static/resources/view/zapret2/ 2>/dev/null || true
    fi
    if [ -d "$SCRIPT_DIR/luci-app-zapret2/root" ]; then
        cp -rf "$SCRIPT_DIR/luci-app-zapret2/root/"* / 2>/dev/null || true
    fi
else
    echo "      Загрузка полного архива из GitHub (ветка zap1)..."
    TMP_SETUP="/tmp/zapret2-setup-$$"
    mkdir -p "$TMP_SETUP"
    if curl -fSL --retry 3 "https://github.com/rock12/zapret2-openwrt/archive/refs/heads/zap1.tar.gz" -o "$TMP_SETUP/repo.tar.gz"; then
        tar -xzf "$TMP_SETUP/repo.tar.gz" -C "$TMP_SETUP"
        SRC_DIR="$(find "$TMP_SETUP" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
        [ -n "$SRC_DIR" ] || SRC_DIR="$TMP_SETUP"
        cp -rf "$SRC_DIR/zapret2/"* "$INSTALL_DIR/" 2>/dev/null || true
        cp -f "$SRC_DIR/zapret2/init.d.sh" /etc/init.d/zapret2
        [ -f "$SRC_DIR/uninstall.sh" ] && cp -f "$SRC_DIR/uninstall.sh" "$INSTALL_DIR/uninstall.sh"
        if [ -d "$SRC_DIR/luci-app-zapret2/htdocs" ]; then
            mkdir -p /www/luci-static/resources/view/zapret2
            cp -rf "$SRC_DIR/luci-app-zapret2/htdocs/luci-static/resources/view/zapret2/"* /www/luci-static/resources/view/zapret2/ 2>/dev/null || true
        fi
        if [ -d "$SRC_DIR/luci-app-zapret2/root" ]; then
            cp -rf "$SRC_DIR/luci-app-zapret2/root/"* / 2>/dev/null || true
        fi
        rm -rf "$TMP_SETUP"
    else
        echo -e "      ${RED}[ОШИБКА] Не удалось скачать архив репозитория!${NC}"
        exit 1
    fi
fi

# 5. Устранение CRLF и установка прав на исполнение
if command -v dos2unix >/dev/null 2>&1; then
    find "$INSTALL_DIR" -type f \( -name "*.sh" -o -name "*.lua" -o -name "*.awk" -o -name "*.txt" -o -name "*.init" -o -name "*.nft" \) -exec dos2unix {} + 2>/dev/null || true
    dos2unix /etc/init.d/zapret2 /opt/zapret2/init.d/openwrt/zapret2 2>/dev/null || true
fi
for f in "$INSTALL_DIR"/*.sh "$INSTALL_DIR"/warp/*.sh "$INSTALL_DIR"/warp/*.awk "$INSTALL_DIR"/warp/*.txt /etc/init.d/zapret2 /opt/zapret2/init.d/openwrt/zapret2; do
    [ -f "$f" ] || continue
    tr -d '\r' < "$f" > "${f}.tmp" && mv -f "${f}.tmp" "$f" 2>/dev/null || true
done
chmod +x "$INSTALL_DIR"/*.sh 2>/dev/null || true
chmod +x /etc/init.d/zapret2
[ -f "$INSTALL_DIR/warp/WARP.conf" ] && chmod 600 "$INSTALL_DIR/warp/WARP.conf"

# Распаковка и установка Lua-модулей z2k и zapret2
gzip -d -k "$INSTALL_DIR"/lua/*.gz 2>/dev/null || true
cp -f "$INSTALL_DIR"/files/lua/*.lua "$INSTALL_DIR"/lua/ 2>/dev/null || true
mkdir -p "$INSTALL_DIR/extra_strats/cache/autocircular"
chown -R daemon:daemon "$INSTALL_DIR/extra_strats" 2>/dev/null || true

# Патч для поддержки repeat=X в LUA desync (обход зарезервированного ключевого слова Lua)
if [ -f "$INSTALL_DIR/lua/zapret-lib.lua" ]; then
    sed -i 's/local repeats = desync.arg.repeats/local repeats = desync.arg.repeats or rawget(desync.arg, string.char(114,101,112,101,97,116))/' "$INSTALL_DIR/lua/zapret-lib.lua" 2>/dev/null || true
fi

# Патч LUAOPT и BLOB_OPTS в init-скриптах для автоподключения модулей ротации, детекции z2k и фейковых блобов
for f in /opt/zapret2/init.d/sysv/functions /opt/zapret2/init.d/openwrt/zapret2; do
    if [ -f "$f" ]; then
        sed -i 's|LUAOPT=.*|LUAOPT="--lua-init=@$ZAPRET_BASE/lua/zapret-lib.lua --lua-init=@$ZAPRET_BASE/lua/zapret-antidpi.lua --lua-init=@$ZAPRET_BASE/lua/zapret-auto.lua --lua-init=@$ZAPRET_BASE/lua/z2k-alert.lua --lua-init=@$ZAPRET_BASE/lua/z2k-quic-silence.lua --lua-init=@$ZAPRET_BASE/lua/z2k-tcp16.lua --lua-init=@$ZAPRET_BASE/lua/z2k-fooling-ext.lua --lua-init=@$ZAPRET_BASE/lua/z2k-range-rand.lua --lua-init=@$ZAPRET_BASE/lua/z2k-modern-core.lua --lua-init=@$ZAPRET_BASE/lua/z2k-state-persist.lua"\nBLOB_OPTS="--blob=quic_google:@$ZAPRET_BASE/files/fake/quic_initial_www_google_com.bin --blob=quic5:@$ZAPRET_BASE/files/fake/quic_5.bin --blob=quic4:@$ZAPRET_BASE/files/fake/quic_4.bin --blob=quic6:@$ZAPRET_BASE/files/fake/quic_6.bin --blob=quic1:@$ZAPRET_BASE/files/fake/quic_1.bin --blob=quic_rutracker:@$ZAPRET_BASE/files/fake/quic_initial_rutracker_org.bin --blob=quic_dbankcloud:@$ZAPRET_BASE/files/fake/quic_initial_dbankcloud_ru.bin --blob=discord_udp:@$ZAPRET_BASE/files/fake/stun.bin --blob=stun:@$ZAPRET_BASE/files/fake/stun.bin --blob=stun_fake:@$ZAPRET_BASE/files/fake/stun.bin --blob=syn_packet:@$ZAPRET_BASE/files/fake/syn_packet.bin --blob=t2:@$ZAPRET_BASE/files/fake/t2.bin --blob=tls_max:@$ZAPRET_BASE/files/fake/tls_clienthello_max_ru.bin --blob=tls_max_ru:@$ZAPRET_BASE/files/fake/tls_clienthello_max_ru.bin --blob=tls_google:@$ZAPRET_BASE/files/fake/tls_clienthello_www_google_com.bin --blob=blob_tls_clienthello_www_google_com:@$ZAPRET_BASE/files/fake/tls_clienthello_www_google_com.bin --blob=tls_clienthello_14:@$ZAPRET_BASE/files/fake/tls_clienthello_14.bin --blob=tls_clienthello_www_google_com:@$ZAPRET_BASE/files/fake/tls_clienthello_www_google_com.bin --blob=tls_clienthello_4pda_to:@$ZAPRET_BASE/files/fake/tls_clienthello_4pda_to.bin --blob=tls_clienthello_vk_com:@$ZAPRET_BASE/files/fake/tls_clienthello_vk_com.bin --blob=tls_clienthello_gosuslugi_ru:@$ZAPRET_BASE/files/fake/tls_clienthello_gosuslugi_ru.bin --blob=tls_clienthello_activated:@$ZAPRET_BASE/files/fake/tls_clienthello_activated.bin --blob=tls_clienthello_www_onetrust_com:@$ZAPRET_BASE/files/fake/tls_clienthello_www_onetrust_com.bin"|g' "$f" 2>/dev/null || true
        sed -i 's|NFQWS2_OPT_BASE=.*|NFQWS2_OPT_BASE="$USEROPT --fwmark=$DESYNC_MARK --bind-fix4 --bind-fix6 $LUAOPT $BLOB_OPTS"|g' "$f" 2>/dev/null || true
    fi
done

# Патч поддержки логов демона в LuCI (/opt/zapret2/init.d/openwrt/zapret2)
OW_INIT="/opt/zapret2/init.d/openwrt/zapret2"
if [ -f "$OW_INIT" ] && ! grep -q "DAEMON_LOG=" "$OW_INIT"; then
    awk '
    /^run_daemon\(\)/ {
        print "DAEMON_CFGNAME=\"main\"\n"
        print $0
        getline; print $0
        while (getline && $0 !~ /^}$/) {
            # skip old body
        }
        print "\tlocal DAEMONBASE=\"$(basename \"$2\")\""
        print "\techo \"Starting daemon $1: $2 $3\""
        print "\tlocal DAEMON_NAME=\"$DAEMONBASE\""
        print "\tlocal DAEMON_IDNUM=$1"
        print "\tlocal DAEMON_PATH=\"$2\""
        print "\tlocal DAEMON_ARGS=\"$3\""
        print "\tlocal DAEMON_LOG="
        print "\tif [ -n \"$DAEMON_LOG_FILE\" ]; then"
        print "\t\tDAEMON_LOG=\"/tmp/zapret2+${DAEMON_NAME}+${DAEMON_IDNUM}+${DAEMON_CFGNAME}.log\""
        print "\t\t[ -f \"$DAEMON_LOG\" ] && rm -f \"$DAEMON_LOG\""
        print "\t\ttouch \"$DAEMON_LOG\""
        print "\t\tchown \"$WS_USER\":\"$WS_USER\" \"$DAEMON_LOG\" 2>/dev/null || true"
        print "\t\tchmod 666 \"$DAEMON_LOG\" 2>/dev/null || true"
        print "\t\tif [ \"$DAEMON_LOG_ENABLE\" = \"1\" ]; then"
        print "\t\t\tDAEMON_ARGS=\"--debug=@$DAEMON_LOG $DAEMON_ARGS\""
        print "\t\tfi"
        print "\tfi"
        print "\tprocd_open_instance"
        print "\tprocd_set_param command $DAEMON_PATH $DAEMON_ARGS"
        print "\tprocd_set_param pidfile $PIDDIR/${DAEMONBASE}_$1.pid"
        print "\tprocd_close_instance"
        print "}"
        next
    }
    { print }
    ' "$OW_INIT" > "${OW_INIT}.tmp" && mv -f "${OW_INIT}.tmp" "$OW_INIT" && chmod +x "$OW_INIT"
fi

# Установка прозрачного туннеля для Telegram (tg-tunnel)
rm -f /etc/nftables.d/90-telegram.nft 2>/dev/null || true
[ -f "$INSTALL_DIR/tg-tunnel.init" ] && cp -f "$INSTALL_DIR/tg-tunnel.init" /etc/init.d/tg-tunnel && chmod +x /etc/init.d/tg-tunnel

if [ ! -x /usr/bin/tg-mtproxy-client ]; then
    TG_ARCH="$(uname -m)"
    TG_URL=""
    case "$TG_ARCH" in
        aarch64*) TG_URL="https://raw.githubusercontent.com/necronicle/z2k/z2k-enhanced/mtproxy-client/builds/tg-mtproxy-client-linux-arm64" ;;
        x86_64*)  TG_URL="https://raw.githubusercontent.com/necronicle/z2k/z2k-enhanced/mtproxy-client/builds/tg-mtproxy-client-linux-amd64" ;;
        arm*)     TG_URL="https://raw.githubusercontent.com/necronicle/z2k/z2k-enhanced/mtproxy-client/builds/tg-mtproxy-client-linux-arm" ;;
        mips*el*) TG_URL="https://raw.githubusercontent.com/necronicle/z2k/z2k-enhanced/mtproxy-client/builds/tg-mtproxy-client-linux-mipsel" ;;
        mips*)    TG_URL="https://raw.githubusercontent.com/necronicle/z2k/z2k-enhanced/mtproxy-client/builds/tg-mtproxy-client-linux-mips" ;;
    esac
    if [ -n "$TG_URL" ]; then
        echo "      -> Скачивание клиента прозрачного туннеля Telegram ($TG_ARCH)..."
        (curl -sSL -k --retry 3 --connect-timeout 15 -o /usr/bin/tg-mtproxy-client "$TG_URL" 2>/dev/null || wget -q --no-check-certificate -O /usr/bin/tg-mtproxy-client "$TG_URL" 2>/dev/null) && chmod +x /usr/bin/tg-mtproxy-client || true
    fi
fi

# Настройка hotplug для восстановления маршрутов WARP
cat > /etc/hotplug.d/iface/99-warp << 'EOF'
[ "$ACTION" = "ifup" ] && [ "$INTERFACE" = "warp" ] || exit 0
ip route replace default dev warp table 100 2>/dev/null || true
[ -x /opt/zapret2/warp.sh ] && /opt/zapret2/warp.sh reload >/dev/null 2>&1 &
exit 0
EOF
chmod +x /etc/hotplug.d/iface/99-warp

# Блокировка QUIC (UDP 443) в файрволе: принуждает YouTube и браузеры мгновенно переходить на TCP без задержек и ошибок потока
uci -q delete firewall.block_quic || true
uci set firewall.block_quic=rule
uci set firewall.block_quic.name='Block-QUIC'
uci set firewall.block_quic.src='lan'
uci set firewall.block_quic.dest='wan'
uci set firewall.block_quic.proto='udp'
uci set firewall.block_quic.dest_port='443'
uci set firewall.block_quic.target='DROP'
uci commit firewall
/etc/init.d/firewall reload 2>/dev/null || true

# 6. Конфигурация UCI по умолчанию
echo -e "\n${YELLOW}[4/7] Настройка конфигурации сервиса и тумблеров игр...${NC}"
if [ -x "$INSTALL_DIR/uci-def-cfg.sh" ]; then
    "$INSTALL_DIR/uci-def-cfg.sh" >/dev/null 2>&1 || true
fi
uci -q set zapret2.config.WS_USER='daemon' || true
uci -q set zapret2.config.DAEMON_LOG_SIZE_MAX='2000' || true
uci -q set zapret2.config.MODE_FILTER='autohostlist' || true
uci -q set zapret2.config.AUTOHOSTLIST_DEBUGLOG='1' || true
uci -q set zapret2.config.NFQWS2_PORTS_TCP='80,443,2053,2083,2087,2096,8443' || true
uci -q set zapret2.config.NFQWS2_PORTS_UDP='1400,3478-3481,5349,19294-19344,50000-65535' || true
uci -q set zapret2.config.NFQWS2_TCP_PKT_OUT='50' || true
uci -q set zapret2.config.NFQWS2_TCP_PKT_IN='20' || true
uci -q set zapret2.config.NFQWS2_UDP_PKT_OUT='8' || true
uci -q set zapret2.config.NFQWS2_UDP_PKT_IN='8' || true
uci -q set zapret2.config.NFQWS2_OPT='--filter-tcp=443,2053,2083,2087,2096,8443 --filter-l7=tls,unknown --hostlist=/opt/zapret2/extra_strats/TCP/YT/List.txt --payload=tls_client_hello,http_req,http_reply,unknown,tls_server_hello --out-range=-s34228 --in-range=-s5556 --lua-desync=multidisorder:pos=1,sniext+1,host+1,midsld-2,midsld,midsld+2,endhost-1 --new --filter-tcp=443 --filter-l7=tls,unknown --hostlist=/opt/zapret2/extra_strats/TCP/YT_GV/List.txt --payload=tls_client_hello,http_req,http_reply,unknown,tls_server_hello --out-range=-s34228 --in-range=-s5556 --lua-desync=multidisorder:pos=1,sniext+1,host+1,midsld-2,midsld,midsld+2,endhost-1 --new --filter-tcp=80,443,2053,2083,2087,2096,8443 --filter-l7=tls --hostlist=/opt/zapret2/extra_strats/TCP/RKN/Discord.txt --hostlist=/opt/zapret2/extra_strats/TCP/RKN/List.txt --hostlist=/opt/zapret2/ipset/zapret-hosts-user.txt --hostlist=/opt/zapret2/ipset/zapret-hosts-auto.txt --hostlist-exclude=/opt/zapret2/ipset/zapret-hosts-user-exclude.txt --hostlist-auto=/opt/zapret2/ipset/zapret-hosts-auto.txt --hostlist-auto-fail-threshold=3 --hostlist-auto-fail-time=60 --hostlist-auto-debug=/opt/zapret2/ipset/zapret-hosts-auto-debug.log --payload=tls_client_hello --lua-desync=fake:blob=stun_fake:repeats=6:tcp_seq=1000:tcp_ack=-66000 --lua-desync=fake:blob=tls_clienthello_vk_com:repeats=6:tcp_seq=1000:tcp_ack=-66000 --lua-desync=multisplit --new --filter-udp=1400,3478-3481,5349,19294-19344,50000-65535 --filter-l7=discord,stun --in-range=x --out-range=-d4 --payload=discord_ip_discovery,stun --lua-desync=fake:payload=all:blob=quic_dbankcloud:repeats=6' || true
uci -q delete zapret2.config.WARP_GAMES || true
uci -q set zapret2.config.run_on_boot='1' || true
uci -q set zapret2.config.WARP_ENABLED='0' || true

# Настройка игровых тумблеров (по умолчанию отключены, включаются по необходимости в LuCI)
for g in WARZONE COMMUNITY BATTLEFIELD6 STEAM EA_ORIGIN BATTLENET EPIC_FORTNITE RIOT_VALORANT ROBLOX APEX_ROCKETLEAGUE UBISOFT LEAGUEOFLEGENDS WARFRAME DEADBYDAYLIGHT ARMA_REFORGER MINECRAFT WARDOGS CUSTOM; do
    if [ -z "$(uci -q get zapret2.config.WARP_GAME_$g)" ]; then
        uci -q set zapret2.config.WARP_GAME_$g='0' || true
    fi
done

# 7. Полное отключение IPv6 (предотвращает утечки трафика мимо Zapret2 и DPI обходов)
echo -e "\n${YELLOW}[5/7] Отключение IPv6 и предотвращение утечек DNS...${NC}"
uci set dhcp.lan.dhcpv6='disabled' 2>/dev/null || true
uci set dhcp.lan.ra='disabled' 2>/dev/null || true
uci -q delete dhcp.lan.ra_flags 2>/dev/null || true
uci -q delete dhcp.lan.ra_slaac 2>/dev/null || true
uci set dhcp.@dnsmasq[0].filter_aaaa='1' 2>/dev/null || true

# Отключение DHCPv6 клиента на внешнем интерфейсе WAN6
if [ -n "$(uci -q get network.wan6)" ]; then
    uci set network.wan6.auto='0' 2>/dev/null || true
fi

# Безопасное отключение IPv6 через sysctl (сохраняя loopback для локальных сокетов)
mkdir -p /etc/sysctl.d
cat > /etc/sysctl.d/99-disable-ipv6.conf << 'EOF'
net.ipv6.conf.all.disable_ipv6 = 0
net.ipv6.conf.default.disable_ipv6 = 0
net.ipv6.conf.lo.disable_ipv6 = 0
net.ipv6.conf.wan.disable_ipv6 = 1
net.ipv6.conf.br-lan.disable_ipv6 = 1
EOF
sysctl -p /etc/sysctl.d/99-disable-ipv6.conf >/dev/null 2>&1 || true

# Настройка DNS-пинов в dnsmasq для стабильной работы Instagram и Discord Voice
uci -q delete dhcp.@dnsmasq[0].address 2>/dev/null || true
uci add_list dhcp.@dnsmasq[0].address='/instagram.com/157.240.238.174' 2>/dev/null || true
uci add_list dhcp.@dnsmasq[0].address='/cdninstagram.com/157.240.238.174' 2>/dev/null || true
uci add_list dhcp.@dnsmasq[0].address='/discord.media/104.25.158.178' 2>/dev/null || true
uci commit dhcp 2>/dev/null || true
/etc/init.d/dnsmasq restart 2>/dev/null || true
/etc/init.d/odhcpd restart 2>/dev/null || true

# 8. Интеллектуальная настройка MTU и TCP MSS Clamping (1 роутер или каскад из 2 роутеров)
echo -e "\n${YELLOW}[6/7] Настройка MTU и защита от фрагментации пакетов...${NC}"
uci set firewall.@zone[1].mtu_fix='1' 2>/dev/null || true
uci commit firewall 2>/dev/null || true

WAN_DEV="$(uci -q get network.wan.device || echo "wan")"
WAN_PROTO="$(uci -q get network.wan.proto || echo "dhcp")"
WAN_IP="$(ip -4 addr show dev "$WAN_DEV" 2>/dev/null | grep -o 'inet [0-9.]*' | cut -d' ' -f2 | head -n 1)"

IS_CASCADE=0
case "$WAN_IP" in
    10.*|192.168.*|172.1[6-9].*|172.2[0-9].*|172.3[0-1].*)
        IS_CASCADE=1
        ;;
esac

if [ "$IS_CASCADE" = "1" ]; then
    echo -e "      ${CYAN}-> Обнаружен каскад из 2 роутеров (WAN IP: $WAN_IP за вышестоящим роутером/ONT)${NC}"
    echo -e "      -> Установка защитного MTU 1480 на WAN (предотвращает дропы десинка и застревание пакетов в Double NAT)"
    uci set network.wan.mtu='1480' 2>/dev/null || true
else
    echo -e "      ${GREEN}-> Обнаружено прямое подключение провайдера (1 роутер)${NC}"
    if [ "$WAN_PROTO" = "pppoe" ]; then
        echo -e "      -> Протокол PPPoE: установка MTU 1492"
        uci set network.wan.mtu='1492' 2>/dev/null || true
    else
        echo -e "      -> Протокол $WAN_PROTO: установка стандартного MTU 1500"
        uci set network.wan.mtu='1500' 2>/dev/null || true
    fi
fi
uci commit network 2>/dev/null || true
uci commit zapret2 2>/dev/null || true

# 9. Запуск сервисов
echo -e "\n${YELLOW}[7/7] Включение автозагрузки и запуск служб...${NC}"
/etc/init.d/zapret2 enable 2>/dev/null || true
/etc/init.d/zapret2 restart 2>/dev/null || true
/etc/init.d/tg-tunnel enable 2>/dev/null || true
/etc/init.d/tg-tunnel restart 2>/dev/null || true
/etc/init.d/https-dns-proxy enable 2>/dev/null || true
/etc/init.d/https-dns-proxy restart 2>/dev/null || true
fw4 reload 2>/dev/null || true

# Перезапуск веб-сервера LuCI для обновления интерфейса
/etc/init.d/uhttpd restart 2>/dev/null || true
/etc/init.d/rpcd restart 2>/dev/null || true

echo ""
echo -e "${GREEN}======================================================================${NC}"
echo -e "${BOLD}${GREEN}           🎉 Установка успешно завершена!                           ${NC}"
echo -e "${GREEN}======================================================================${NC}"
echo ""
echo -e "Веб-интерфейс доступен в LuCI:"
echo -e "  👉 ${BOLD}http://192.168.1.1${NC} -> меню ${CYAN}Службы${NC} -> ${CYAN}Zapret 2${NC}"
echo -e "  👉 Вкладка ${CYAN}Cloudflare WARP (Games)${NC}: управление игровыми тумблерами"
echo ""
echo -e "Полезные команды:"
echo -e "  - Проверить статус WARP:    ${BOLD}/opt/zapret2/warp.sh status${NC}"
echo -e "  - Найти минимальный пинг:   ${BOLD}/opt/zapret2/warp.sh scout${NC}"
echo -e "  - Логи автоподбора:         ${BOLD}tail -f /tmp/autolearn.log${NC}"
echo -e "  - Логи WARP:                ${BOLD}cat /tmp/zapret2-warp.log${NC}"
echo -e "  - Полное удаление комплекса: ${BOLD}/opt/zapret2/uninstall.sh${NC}"
echo ""
