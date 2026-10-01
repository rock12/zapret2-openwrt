#!/bin/sh /etc/rc.common
# Copyright (c) 2024 remittor

# check if script is running during the image creation process (Image Builder).
# $IPKG_INSTROOT is used by opkg, $ROOT is used by apk:
[ -n "$IPKG_INSTROOT" ] || [ -n "$ROOT" ] && exit 0

USE_PROCD=1
# after network, firewall, and wan
START=90

SCRIPT_FILENAME=$1

. /opt/zapret2/comfunc.sh

if ! is_valid_config ; then
	logger -p err -t $ZAP_LOG_TAG "Wrong main config: $ZAPRET_CONFIG"
	exit 91
fi

. $ZAPRET_ORIG_INITD

EXEDIR=/opt/$ZAPRET_CFG_NAME
ZAPRET_BASE=/opt/$ZAPRET_CFG_NAME

mkdir -p "$ZAPRET_BASE/extra_strats/cache/autocircular" 2>/dev/null
chown -R daemon:daemon "$ZAPRET_BASE/extra_strats" 2>/dev/null

LUAOPT="--lua-init=@$ZAPRET_BASE/lua/zapret-lib.lua --lua-init=@$ZAPRET_BASE/lua/zapret-antidpi.lua"
[ -f "$ZAPRET_BASE/lua/zapret-auto.lua" ] && LUAOPT="$LUAOPT --lua-init=@$ZAPRET_BASE/lua/zapret-auto.lua"
[ -f "$ZAPRET_BASE/lua/z2k-alert.lua" ] && LUAOPT="$LUAOPT --lua-init=@$ZAPRET_BASE/lua/z2k-alert.lua"
[ -f "$ZAPRET_BASE/lua/z2k-quic-silence.lua" ] && LUAOPT="$LUAOPT --lua-init=@$ZAPRET_BASE/lua/z2k-quic-silence.lua"
[ -f "$ZAPRET_BASE/lua/z2k-tcp16.lua" ] && LUAOPT="$LUAOPT --lua-init=@$ZAPRET_BASE/lua/z2k-tcp16.lua"
[ -f "$ZAPRET_BASE/lua/z2k-fooling-ext.lua" ] && LUAOPT="$LUAOPT --lua-init=@$ZAPRET_BASE/lua/z2k-fooling-ext.lua"
[ -f "$ZAPRET_BASE/lua/z2k-range-rand.lua" ] && LUAOPT="$LUAOPT --lua-init=@$ZAPRET_BASE/lua/z2k-range-rand.lua"
[ -f "$ZAPRET_BASE/lua/z2k-modern-core.lua" ] && LUAOPT="$LUAOPT --lua-init=@$ZAPRET_BASE/lua/z2k-modern-core.lua"
[ -f "$ZAPRET_BASE/lua/z2k-state-persist.lua" ] && LUAOPT="$LUAOPT --lua-init=@$ZAPRET_BASE/lua/z2k-state-persist.lua"

BLOB_OPTS=""
for _bpair in \
	quic_google:quic_initial_www_google_com.bin \
	quic5:quic_5.bin \
	quic4:quic_4.bin \
	quic6:quic_6.bin \
	quic1:quic_1.bin \
	quic_rutracker:quic_initial_rutracker_org.bin \
	quic_dbankcloud:quic_initial_dbankcloud_ru.bin \
	discord_udp:stun.bin \
	stun:stun.bin \
	stun_fake:stun.bin \
	syn_packet:syn_packet.bin \
	t2:t2.bin \
	tls_max:tls_clienthello_max_ru.bin \
	tls_max_ru:tls_clienthello_max_ru.bin \
	tls_google:tls_clienthello_www_google_com.bin \
	blob_tls_clienthello_www_google_com:tls_clienthello_www_google_com.bin \
	tls_clienthello_14:tls_clienthello_14.bin \
	tls_clienthello_www_google_com:tls_clienthello_www_google_com.bin \
	tls_clienthello_4pda_to:tls_clienthello_4pda_to.bin \
	tls_clienthello_vk_com:tls_clienthello_vk_com.bin \
	tls_clienthello_gosuslugi_ru:tls_clienthello_gosuslugi_ru.bin \
	tls_clienthello_activated:tls_clienthello_activated.bin \
	tls_clienthello_www_onetrust_com:tls_clienthello_www_onetrust_com.bin
do
	_bname="${_bpair%%:*}"
	_bfile="$ZAPRET_BASE/files/fake/${_bpair#*:}"
	[ -s "$_bfile" ] && BLOB_OPTS="$BLOB_OPTS --blob=$_bname:@$_bfile"
done

NFQWS2_OPT_BASE="$USEROPT --fwmark=$DESYNC_MARK --bind-fix4 --bind-fix6 $LUAOPT $BLOB_OPTS"

is_run_on_boot && IS_RUN_ON_BOOT=1 || IS_RUN_ON_BOOT=0


function enable
{
	local run_on_boot=""
	patch_luci_header_ut
	if [ "$IS_RUN_ON_BOOT" = "1" ]; then
		if [ -n "$ZAPRET_CFG_SEC_NAME" ]; then
			run_on_boot=$( get_run_on_boot_option )
			if [ $run_on_boot != 1 ]; then
				logger -p notice -t $ZAP_LOG_TAG "Attempt to enable service, but service blocked!"
				return 61
			fi
		fi
	fi
	if [ -n "$ZAPRET_CFG_SEC_NAME" ]; then
		uci set $ZAPRET_CFG_SEC.run_on_boot=1
		uci commit
	fi
	/bin/sh /etc/rc.common $ZAPRET_ORIG_INITD enable
}

function enabled
{
	local run_on_boot=""
	if [ -n "$ZAPRET_CFG_SEC_NAME" ]; then
		run_on_boot=$( get_run_on_boot_option )
		if [ $run_on_boot != 1 ]; then
			if [ "$IS_RUN_ON_BOOT" = "1" ]; then
				logger -p notice -t $ZAP_LOG_TAG "Service is blocked!"
			fi
			return 61
		fi
	fi
	/bin/sh /etc/rc.common $ZAPRET_ORIG_INITD enabled
}

function boot
{
	local run_on_boot=""
	patch_luci_header_ut
	if [ "$IS_RUN_ON_BOOT" = "1" ]; then
		if [ -n "$ZAPRET_CFG_SEC_NAME" ]; then
			run_on_boot=$( get_run_on_boot_option )
			if [ $run_on_boot != 1 ]; then
				logger -p notice -t $ZAP_LOG_TAG "Attempt to run service on boot! Service is blocked!"
				return 61
			fi
		fi
	fi
	start "$@"
}

function start
{
	[ -x /opt/zapret2/sync_config.sh ] && /opt/zapret2/sync_config.sh
	init_before_start "$DAEMON_LOG_ENABLE" "$DAEMON_LOG_SIZE_MAX"
	/bin/sh /etc/rc.common $ZAPRET_ORIG_INITD start "$@"
	if [ -x /opt/zapret2/warp.sh ] && [ "$(uci -q get zapret2.config.WARP_ENABLED)" = "1" ]; then
		(exec 1000>&-; /opt/zapret2/warp.sh up >/dev/null 2>&1) &
	fi
	if [ -x /opt/zapret2/autolearn-cidr.sh ]; then
		(exec 1000>&-; /opt/zapret2/autolearn-cidr.sh daemon >/dev/null 2>&1) &
	fi
}

function stop
{
	[ -f /tmp/zapret2_autolearn.lock ] && kill $(cat /tmp/zapret2_autolearn.lock 2>/dev/null) 2>/dev/null || true
	killall autolearn-cidr.sh 2>/dev/null || true
	rm -f /tmp/zapret2_autolearn.lock
	if [ -x /opt/zapret2/warp.sh ]; then
		/opt/zapret2/warp.sh down >/dev/null 2>&1 || true
	fi
	/bin/sh /etc/rc.common $ZAPRET_ORIG_INITD stop "$@"
}

function restart
{
	[ -x /opt/zapret2/sync_config.sh ] && /opt/zapret2/sync_config.sh
	init_before_start "$DAEMON_LOG_ENABLE" "$DAEMON_LOG_SIZE_MAX"
	/bin/sh /etc/rc.common $ZAPRET_ORIG_INITD restart "$@"
	if [ -x /opt/zapret2/warp.sh ]; then
		if [ "$(uci -q get zapret2.config.WARP_ENABLED)" = "1" ]; then
			(exec 1000>&-; /opt/zapret2/warp.sh up >/dev/null 2>&1) &
		else
			/opt/zapret2/warp.sh down >/dev/null 2>&1 || true
		fi
	fi
	[ -f /tmp/zapret2_autolearn.lock ] && kill $(cat /tmp/zapret2_autolearn.lock 2>/dev/null) 2>/dev/null || true
	killall autolearn-cidr.sh 2>/dev/null || true
	rm -f /tmp/zapret2_autolearn.lock
	if [ -x /opt/zapret2/autolearn-cidr.sh ]; then
		(exec 1000>&-; /opt/zapret2/autolearn-cidr.sh daemon >/dev/null 2>&1) &
	fi
}

function reload_service
{
	restart "$@"
}

