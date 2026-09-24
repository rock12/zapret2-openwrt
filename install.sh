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
echo -e "${YELLOW}[1/6] Проверка пакетного менеджера OpenWrt...${NC}"
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
echo -e "\n${YELLOW}[2/6] Установка системных зависимостей...${NC}"
if [ "$PKG_MGR" = "apk" ]; then
    echo "      Обновление индексов пакетов (apk update)..."
    apk update || true
    
    REQUIRED_PKGS="curl ca-bundle ca-certificates nftables kmod-nft-core kmod-nft-nat kmod-nf-conntrack"
    AMNEZIA_PKGS="kmod-amneziawg amneziawg-tools luci-proto-amneziawg bind-tools"
    
    for p in $REQUIRED_PKGS; do
        if apk info -e "$p" >/dev/null 2>&1; then
            echo -e "      ${GREEN}✓${NC} $p (уже установлен)"
        else
            echo "      -> Установка $p..."
            apk add "$p" || echo -e "      ${YELLOW}[!] Не удалось установить $p (проверьте репозитории)${NC}"
        fi
    done

    for p in $AMNEZIA_PKGS; do
        if apk info -e "$p" >/dev/null 2>&1; then
            echo -e "      ${GREEN}✓${NC} $p (уже установлен)"
        else
            apk add "$p" 2>/dev/null || true
        fi
    done
    if ! apk info -e kmod-amneziawg >/dev/null 2>&1 && ! apk info -e kmod-wireguard >/dev/null 2>&1; then
        echo "      -> Установка WireGuard как альтернативного провайдера..."
        apk add kmod-wireguard wireguard-tools luci-proto-wireguard 2>/dev/null || true
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

    REQUIRED_PKGS="curl ca-bundle ca-certificates nftables kmod-nft-core kmod-nft-nat kmod-nf-conntrack"
    AMNEZIA_PKGS="kmod-amneziawg amneziawg-tools luci-proto-amneziawg bind-tools"

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
    if ! opkg list-installed | grep -qw "^kmod-amneziawg" && ! opkg list-installed | grep -qw "^kmod-wireguard"; then
        echo "      -> Установка WireGuard как альтернативного провайдера..."
        opkg install kmod-wireguard wireguard-tools luci-proto-wireguard 2>/dev/null || true
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
echo -e "\n${YELLOW}[3/6] Настройка каталогов и компонентов zapret2...${NC}"
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

# 5. Установка прав на исполнение
chmod +x "$INSTALL_DIR"/*.sh 2>/dev/null || true
chmod +x /etc/init.d/zapret2
[ -f "$INSTALL_DIR/warp/WARP.conf" ] && chmod 600 "$INSTALL_DIR/warp/WARP.conf"

# Настройка hotplug для восстановления маршрутов WARP
cat > /etc/hotplug.d/iface/99-warp << 'EOF'
[ "$ACTION" = "ifup" ] && [ "$INTERFACE" = "warp" ] || exit 0
ip route replace default dev warp table 100 2>/dev/null || true
[ -x /opt/zapret2/warp.sh ] && /opt/zapret2/warp.sh reload >/dev/null 2>&1 &
exit 0
EOF
chmod +x /etc/hotplug.d/iface/99-warp

# 6. Конфигурация UCI по умолчанию
echo -e "\n${YELLOW}[4/6] Настройка конфигурации сервиса и тумблеров игр...${NC}"
if [ -x "$INSTALL_DIR/uci-def-cfg.sh" ]; then
    "$INSTALL_DIR/uci-def-cfg.sh" >/dev/null 2>&1 || true
fi
uci -q set zapret2.config.WS_USER='daemon' || true
uci -q set zapret2.config.DAEMON_LOG_SIZE_MAX='2000' || true
uci -q delete zapret2.config.WARP_GAMES || true
uci -q set zapret2.config.run_on_boot='1' || true
uci -q set zapret2.config.WARP_ENABLED='1' || true
uci -q set zapret2.config.WARP_TELEGRAM='1' || true

# Включение игр по умолчанию (с возможностью отключения в LuCI)
for g in WARZONE BATTLEFIELD6 STEAM EA_ORIGIN BATTLENET EPIC_FORTNITE RIOT_VALORANT ROBLOX APEX_ROCKETLEAGUE UBISOFT LEAGUEOFLEGENDS WARFRAME DEADBYDAYLIGHT ARMA_REFORGER MINECRAFT CUSTOM; do
    if [ -z "$(uci -q get zapret2.config.WARP_GAME_$g)" ]; then
        uci -q set zapret2.config.WARP_GAME_$g='1' || true
    fi
done
uci commit zapret2 2>/dev/null || true

# 7. Запуск сервисов
echo -e "\n${YELLOW}[5/6] Включение автозагрузки и запуск zapret2...${NC}"
/etc/init.d/zapret2 enable 2>/dev/null || true
/etc/init.d/zapret2 restart 2>/dev/null || true

# Перезапуск веб-сервера LuCI для обновления интерфейса
/etc/init.d/uhttpd restart 2>/dev/null || true
/etc/init.d/rpcd restart 2>/dev/null || true

# 8. Автоматический подбор эндпоинта с минимальным пингом
echo -e "\n${YELLOW}[6/6] Сканирование серверов Cloudflare (WARP Scout)...${NC}"
if [ -x "$INSTALL_DIR/warp.sh" ]; then
    "$INSTALL_DIR/warp.sh" scout || true
fi

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
echo ""
