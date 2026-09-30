#!/bin/sh
# ==============================================================================
# Скрипт полного удаления zapret2-openwrt + AmneziaWG WARP + Telegram Tunnel
# Репозиторий: https://github.com/rock12/zapret2-openwrt (ветка zap1)
# ==============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo ""
echo -e "${CYAN}======================================================================${NC}"
echo -e "${BOLD}${RED}          Удаление zapret2-openwrt и всех компонентов                 ${NC}"
echo -e "${CYAN}======================================================================${NC}"
echo ""

# 1. Проверка прав root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}[ОШИБКА] Скрипт должен быть запущен с правами root!${NC}"
    exit 1
fi

echo -e "${YELLOW}[1/5] Остановка и отключение всех служб...${NC}"

# Остановка WARP
if [ -x /opt/zapret2/warp.sh ]; then
    /opt/zapret2/warp.sh down >/dev/null 2>&1 || true
fi
ip link del dev warp 2>/dev/null || true

# Остановка служб init.d
/etc/init.d/zapret2 stop >/dev/null 2>&1 || true
/etc/init.d/zapret2 disable >/dev/null 2>&1 || true

/etc/init.d/tg-tunnel stop >/dev/null 2>&1 || true
/etc/init.d/tg-tunnel disable >/dev/null 2>&1 || true

/etc/init.d/tg-ws-proxy stop >/dev/null 2>&1 || true
/etc/init.d/tg-ws-proxy disable >/dev/null 2>&1 || true

# Принудительное завершение фоновых процессов
killall -9 nfqws2 tg-mtproxy-client tg-ws-proxy-go autolearn-cidr.sh 2>/dev/null || true
[ -f /tmp/zapret2_autolearn.lock ] && kill -9 $(cat /tmp/zapret2_autolearn.lock 2>/dev/null) 2>/dev/null || true
rm -f /tmp/zapret2_autolearn.lock

echo -e "      ${GREEN}✓${NC} Службы и процессы остановлены"

echo -e "\n${YELLOW}[2/5] Очистка правил nftables и маршрутизации (PBR)...${NC}"

# Очистка nftables
rm -f /etc/nftables.d/90-telegram.nft
nft delete table inet zapret >/dev/null 2>&1 || true
nft delete table inet zapret2 >/dev/null 2>&1 || true
nft delete table inet zapret2_warp >/dev/null 2>&1 || true
nft delete table inet warp >/dev/null 2>&1 || true
nft delete table inet tg_tunnel >/dev/null 2>&1 || true

# Очистка PBR (Policy Based Routing)
ip rule del fwmark 0x1000 2>/dev/null || true
ip rule del fwmark 0x40000000 2>/dev/null || true
ip route flush table 100 2>/dev/null || true
rm -f /etc/hotplug.d/iface/99-warp

# Перезагрузка файрвола OpenWrt для восстановления чистого состояния
if command -v fw4 >/dev/null 2>&1; then
    fw4 reload >/dev/null 2>&1 || true
elif command -v fw3 >/dev/null 2>&1; then
    fw3 reload >/dev/null 2>&1 || true
fi

echo -e "      ${GREEN}✓${NC} Правила фаервола и таблицы маршрутов сброшены"

echo -e "\n${YELLOW}[3/5] Удаление файлов программы, веб-интерфейса и бинарников...${NC}"

# Удаление каталога /opt/zapret2
rm -rf /opt/zapret2

# Удаление init-скриптов
rm -f /etc/init.d/zapret2
rm -f /etc/init.d/tg-tunnel
rm -f /etc/init.d/tg-ws-proxy

# Удаление бинарников прокси Telegram
rm -f /usr/bin/tg-mtproxy-client
rm -f /usr/bin/tg-ws-proxy-go

# Удаление файлов веб-интерфейса LuCI
rm -rf /www/luci-static/resources/view/zapret2
rm -f /usr/share/luci/menu.d/luci-app-zapret2.json
rm -f /usr/share/rpcd/acl.d/luci-app-zapret2.json

# Удаление временных файлов и логов
rm -f /tmp/zapret2* /tmp/autolearn* /tmp/tg-* /tmp/warp*

echo -e "      ${GREEN}✓${NC} Файлы и скрипты удалены"

echo -e "\n${YELLOW}[4/5] Очистка конфигураций UCI...${NC}"

# Удаление UCI секции zapret2
uci -q delete zapret2 >/dev/null 2>&1 || true
uci -q delete ucitrack.@zapret2[0] >/dev/null 2>&1 || true
rm -f /etc/config/zapret2

# Восстановление настроек dnsmasq и firewall (удаление кастомных записей и правил блокировки QUIC)
uci del_list dhcp.@dnsmasq[0].address='/instagram.com/31.13.72.36' >/dev/null 2>&1 || true
uci del_list dhcp.@dnsmasq[0].address='/cdninstagram.com/31.13.72.36' >/dev/null 2>&1 || true
uci del_list dhcp.@dnsmasq[0].address='/instagram.com/157.240.238.174' >/dev/null 2>&1 || true
uci del_list dhcp.@dnsmasq[0].address='/cdninstagram.com/157.240.238.174' >/dev/null 2>&1 || true
uci del_list dhcp.@dnsmasq[0].address='/discord.media/104.25.158.178' >/dev/null 2>&1 || true
uci -q delete firewall.block_quic >/dev/null 2>&1 || true
uci commit firewall >/dev/null 2>&1 || true
uci commit dhcp >/dev/null 2>&1 || true
/etc/init.d/dnsmasq restart >/dev/null 2>&1 || true
/etc/init.d/firewall reload >/dev/null 2>&1 || true

# Удаление пакетов через менеджер (если были установлены)
if command -v apk >/dev/null 2>&1; then
    apk del luci-app-zapret2 zapret2 >/dev/null 2>&1 || true
elif command -v opkg >/dev/null 2>&1; then
    opkg remove luci-app-zapret2 zapret2 >/dev/null 2>&1 || true
fi

echo -e "      ${GREEN}✓${NC} Конфигурации очищены"

echo -e "\n${YELLOW}[5/5] Перезапуск веб-сервера роутера...${NC}"
/etc/init.d/rpcd restart >/dev/null 2>&1 || true
/etc/init.d/uhttpd restart >/dev/null 2>&1 || true

echo ""
echo -e "${GREEN}======================================================================${NC}"
echo -e "${BOLD}${GREEN}        ✅ zapret2-openwrt успешно и полностью удален!                ${NC}"
echo -e "${GREEN}======================================================================${NC}"
echo -e "Роутер возвращен в исходное состояние. Дополнительная перезагрузка не требуется."
echo ""
