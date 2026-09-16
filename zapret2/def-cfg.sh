#!/bin/sh
# Copyright (c) 2025 remittor

function set_cfg_reset_values
{
	local cfgname=${1:-$ZAPRET_CFG_NAME}
	local TAB="$( printf '\t' )"
	uci batch <<-EOF
		set $cfgname.config.run_on_boot='0'
		# settings for zapret service
		set $cfgname.config.FWTYPE='nftables'
		set $cfgname.config.POSTNAT='1'
		set $cfgname.config.FLOWOFFLOAD='none'
		set $cfgname.config.INIT_APPLY_FW='1'
		set $cfgname.config.DISABLE_IPV4='0'
		set $cfgname.config.DISABLE_IPV6='1'
		set $cfgname.config.FILTER_TTL_EXPIRED_ICMP='1'
		set $cfgname.config.MODE_FILTER='hostlist'
		set $cfgname.config.DISABLE_CUSTOM='1'
		set $cfgname.config.WS_USER='daemon'
		set $cfgname.config.DAEMON_LOG_ENABLE='0'
		set $cfgname.config.DAEMON_LOG_SIZE_MAX='2000'
		set $cfgname.config.DAEMON_LOG_FILE='/tmp/zapret2+<DAEMON_NAME>+<DAEMON_IDNUM>+<DAEMON_CFGNAME>.log'
		# autohostlist options
		set $cfgname.config.AUTOHOSTLIST_INCOMING_MAXSEQ='4096'
		set $cfgname.config.AUTOHOSTLIST_RETRANS_MAXSEQ='32768'
		set $cfgname.config.AUTOHOSTLIST_RETRANS_RESET='1'
		set $cfgname.config.AUTOHOSTLIST_RETRANS_THRESHOLD='3'
		set $cfgname.config.AUTOHOSTLIST_FAIL_THRESHOLD='3'
		set $cfgname.config.AUTOHOSTLIST_FAIL_TIME='60'
		set $cfgname.config.AUTOHOSTLIST_UDP_IN='1'
		set $cfgname.config.AUTOHOSTLIST_UDP_OUT='4'
		set $cfgname.config.AUTOHOSTLIST_DEBUGLOG='0'
		# nfqws options
		set $cfgname.config.NFQWS2_ENABLE='1'
		set $cfgname.config.DESYNC_MARK='0x40000000'
		set $cfgname.config.DESYNC_MARK_POSTNAT='0x20000000'
		set $cfgname.config.FILTER_MARK='$TAB'
		set $cfgname.config.NFQWS2_PORTS_TCP='80,443'
		set $cfgname.config.NFQWS2_PORTS_UDP='443'
		set $cfgname.config.NFQWS2_TCP_PKT_OUT='20'
		set $cfgname.config.NFQWS2_TCP_PKT_IN='10'
		set $cfgname.config.NFQWS2_UDP_PKT_OUT='5'
		set $cfgname.config.NFQWS2_UDP_PKT_IN='3'
		set $cfgname.config.NFQWS2_PORTS_TCP_KEEPALIVE='0'
		set $cfgname.config.NFQWS2_PORTS_UDP_KEEPALIVE='0'
		# warp settings
		set $cfgname.config.WARP_ENABLED='0'
		set $cfgname.config.WARP_GAMES='1'
		set $cfgname.config.WARP_TELEGRAM='1'
		# save changes
		commit $cfgname
	EOF
	return 0
}

function clear_nfqws_strat
{
	local cfgname=${1:-$ZAPRET_CFG_NAME}
	local TAB="$( printf '\t' )"
	uci batch <<-EOF
		set $cfgname.config.MODE_FILTER='hostlist'
		set $cfgname.config.NFQWS2_PORTS_TCP='80,443'
		set $cfgname.config.NFQWS2_PORTS_UDP='443'
		set $cfgname.config.NFQWS2_OPT='$TAB'
		commit $cfgname
	EOF
}

function set_cfg_nfqws_strat
{
	local strat=${1:--}
	local cfgname=${2:-$ZAPRET_CFG_NAME}
	local TAB="$( printf '\t' )"
    
	uci batch <<-EOF
		set $cfgname.config.MODE_FILTER='hostlist'
		commit $cfgname
	EOF
	if [ "$strat" = "empty" ]; then
		clear_nfqws_strat $cfgname
	fi
	if [ "$strat" = "default" ]; then
		uci batch <<-EOF
			set $cfgname.config.NFQWS2_PORTS_TCP='80,443'
			set $cfgname.config.NFQWS2_PORTS_UDP='443'
			set $cfgname.config.NFQWS2_OPT="
				--comment=Strategy__$strat
				
				--filter-tcp=80
				--filter-l7=http <HOSTLIST>
				--payload=http_req
				--lua-desync=fake:blob=fake_default_http:tcp_md5
				--lua-desync=multisplit:pos=method+2
				
				--new
				--filter-tcp=443
				--filter-l7=tls <HOSTLIST>
				--payload=tls_client_hello
				--lua-desync=fake:blob=fake_default_tls:tcp_md5:tcp_seq=-10000
				--lua-desync=multidisorder:pos=1,midsld
				
				--new
				--filter-udp=443
				--filter-l7=quic <HOSTLIST_NOAUTO>
				--payload=quic_initial
				--lua-desync=fake:blob=fake_default_quic:repeats=6
			"
			commit $cfgname
		EOF
	fi
	if [ "$strat" = "v1_by_Schiz23" ]; then
		uci batch <<-EOF
			set $cfgname.config.NFQWS2_PORTS_TCP='80,443'
			set $cfgname.config.NFQWS2_PORTS_UDP='443'
			set $cfgname.config.NFQWS2_OPT="
				--comment=Strategy__$strat
				
				--filter-tcp=80
				--filter-l7=http <HOSTLIST>
				--payload=http_req
				--lua-desync=fake:blob=fake_default_http:tcp_md5
				--lua-desync=multisplit:pos=method+2
				
				--new
				--filter-tcp=443
				--filter-l7=tls <HOSTLIST>
				--lua-desync=fake:blob=fake_default_tls:ip_ttl=1:ip6_ttl=1:tls_mod=rnd,rndsni,padencap
				--lua-desync=multidisorder:payload=tls_client_hello:pos=3
				
				--new
				--filter-udp=443
				--filter-l7=quic <HOSTLIST_NOAUTO>
				--lua-desync=fake:blob=fake_default_quic:repeats=11:payload=all:out_range=-d10
			"
			commit $cfgname
		EOF
	fi
	if [ "$strat" = "v2_by_Schiz23" ]; then
		uci batch <<-EOF
			set $cfgname.config.NFQWS2_PORTS_TCP='80,443'
			set $cfgname.config.NFQWS2_PORTS_UDP='443'
			set $cfgname.config.NFQWS2_OPT="
				--comment=Strategy__$strat
				
				--filter-tcp=80
				--filter-l7=http <HOSTLIST>
				--payload=http_req
				--lua-desync=fake:blob=fake_default_http:tcp_md5
				--lua-desync=multisplit:pos=method+2
				
				--new
				--filter-tcp=443
				--filter-l7=tls <HOSTLIST>
				--payload=tls_client_hello
				--lua-desync=multidisorder:payload=tls_client_hello:pos=100,midsld,sniext+1,endhost-2,-10
				--lua-desync=send:sni=.microsoft
				
				--new
				--filter-udp=443
				--filter-l7=quic <HOSTLIST_NOAUTO>
				--payload=quic_initial
				--lua-desync=fake:blob=fake_default_quic:repeats=11
			"
			commit $cfgname
		EOF
	fi
	if [ "$strat" = "v1_by_AnonymTsk" ]; then
		uci batch <<-EOF
			set $cfgname.config.NFQWS2_PORTS_TCP='80,443'
			set $cfgname.config.NFQWS2_PORTS_UDP='443'
			set $cfgname.config.NFQWS2_OPT="
				--comment=Strategy__$strat
				
				--blob=blob_tls_clienthello_www_google_com:@/opt/zapret2/files/fake/tls_clienthello_www_google_com.bin 
				--blob=blob_quic_initial_www_google_com:@/opt/zapret2/files/fake/quic_initial_www_google_com.bin
				
				--filter-tcp=443,80
				--filter-l7=http,tls <HOSTLIST>
				--payload=tls_client_hello
				--lua-desync=fake:blob=fake_default_tls:tls_mod=rnd,dupsid,sni=www.google.com:tcp_ts=-1000
				--lua-desync=multidisorder:pos=1,midsld,sniext+1,endhost-2,-10:seqovl=1:seqovl_pattern=blob_tls_clienthello_www_google_com:tcp_ts_up
				--payload=http_req
				--lua-desync=http_methodeol:badsum
				
				--new
				--filter-udp=443
				--filter-l7=quic <HOSTLIST_NOAUTO>
				--payload=quic_initial
				--lua-desync=fake:blob=blob_quic_initial_www_google_com:repeats=11
				
				--new
				--filter-udp=590-600,1400,3478-3481,5349,19294-19344,50000-65535
				--filter-l7=wireguard,stun,discord,mtproto
				--out-range=-n1
				--payload=wireguard_initiation,wireguard_response,wireguard_cookie,stun,discord_ip_discovery,mtproto_initial
				--lua-desync=fake:blob=quic_initial:repeats=6
			"
			commit $cfgname
		EOF
	fi
	if [ "$strat" = "v1_by_Routerich" ]; then
		uci batch <<-EOF
			set $cfgname.config.NFQWS2_PORTS_TCP='80,443'
			set $cfgname.config.NFQWS2_PORTS_UDP='443'
			set $cfgname.config.NFQWS2_OPT="
				--comment=Strategy__$strat
				
				--blob=blob_tls_clienthello_www_google_com:@/opt/zapret2/files/fake/tls_clienthello_www_google_com.bin
				--blob=blob_tls_clienthello_vk_com:@/opt/zapret2/files/fake/tls_clienthello_vk_com.bin
				--blob=blob_tls_clienthello_gosuslugi_ru:@/opt/zapret2/files/fake/tls_clienthello_gosuslugi_ru.bin
				--blob=blob_tls_clienthello_www_onetrust_com:@/opt/zapret2/files/fake/tls_clienthello_www_onetrust_com.bin
				--blob=blob_tls_clienthello_t2_ru:@/opt/zapret2/files/fake/t2.bin
				--blob=blob_tls_clienthello_www_4pda_to:@/opt/zapret2/files/fake/4pda.bin
				
				--filter-tcp=443
				--filter-l3=ipv4
				--filter-l7=tls
				--hostlist=/opt/zapret2/ipset/zapret-hosts-google.txt
				--out-range=-s34228
				--in-range=-s5556 --lua-desync=circular:fails=2:maxtime=60
				--in-range=x
				--payload=tls_client_hello
				--lua-desync=fake:blob=0x0F0F0F0F:tcp_seq=-10000:tcp_ack=-66000:badsum:strategy=1
				--lua-desync=fake:blob=blob_tls_clienthello_www_google_com:optional:tcp_seq=-10000:tcp_ack=-66000:badsum:tls_mod=rnd,dupsid,sni=ggpht.com:strategy=1
				--lua-desync=multisplit:pos=2,sld:seqovl=620:seqovl_pattern=blob_tls_clienthello_www_google_com:strategy=1
				--lua-desync=fake:blob=0x00000000:tcp_ack=-66000:strategy=2
				--lua-desync=fake:blob=blob_tls_clienthello_www_google_com:tls_mod=rnd,dupsid,rndsni,padencap:tcp_ack=-66000:strategy=2
				--lua-desync=multisplit:pos=2,endhost:strategy=2
				--lua-desync=multisplit:pos=1:seqovl=681:seqovl_pattern=blob_tls_clienthello_www_google_com:ip_id=zero:strategy=3
				--lua-desync=multisplit:pos=1,sniext+1:seqovl=1:strategy=4
				--lua-desync=multisplit:seqovl=681:seqovl_pattern=blob_tls_clienthello_www_google_com:strategy=5
				--lua-desync=fake:blob=blob_tls_clienthello_www_google_com:tcp_seq=0:tcp_ack=-66000:badsum:tls_mod=rnd,dupsid,sni=fonts.google.com:strategy=6
				--lua-desync=fake:blob=0x0F0F0F0F:tcp_seq=0:tcp_ack=-66000:badsum:tls_mod=none:strategy=6
				--lua-desync=fakeddisorder:pos=10,midsld:seqovl=336:seqovl_pattern=blob_tls_clienthello_gosuslugi_ru:pattern=blob_tls_clienthello_vk_com:tcp_seq=0:tcp_ack=-66000:badsum:strategy=6
				--lua-desync=multidisorder:pos=7,sld+1:strategy=7
				--lua-desync=multidisorder:pos=1,midsld,endhost-1:strategy=8
				--lua-desync=fake:blob=0x00000000:tcp_seq=-10000:tcp_ack=-66000:repeats=2:strategy=9
				--lua-desync=fake:blob=fake_default_tls:tcp_seq=-10000:tcp_ack=-66000:repeats=2:tls_mod=rnd,dupsid,sni=www.google.com:strategy=9
				--lua-desync=multisplit:pos=1,midsld:strategy=9
				--lua-desync=multidisorder:pos=1,midsld:strategy=10
				--lua-desync=multisplit:pos=1,2:seqovl=4:seqovl_pattern=blob_tls_clienthello_www_google_com:strategy=11
				--lua-desync=multidisorder:pos=2,5,105,host+5,sld-1,endsld-5,endsld:strategy=12
				--lua-desync=fake:blob=0x0F0F0F0F:badsum:tcp_seq=-10000:tcp_ack=-66000:strategy=13
				--lua-desync=fake:blob=blob_tls_clienthello_www_google_com:badsum:tcp_seq=-10000:tcp_ack=-66000:tls_mod=rnd,dupsid,sni=ggpht.com:strategy=13
				--lua-desync=multisplit:pos=2,sld:seqovl=2108:seqovl_pattern=blob_tls_clienthello_www_google_com:strategy=13
				--lua-desync=hostfakesplit:midhost=host-2:host=rzd.ru:tcp_seq=0:tcp_ack=-66000:badsum:strategy=14:final
				
				--new
				--filter-tcp=443
				--filter-l3=ipv4
				--filter-l7=tls <HOSTLIST>
				--out-range=-s34228
				--in-range=-s5556 --lua-desync=circular:fails=2:maxtime=60
				--in-range=x
				--payload=tls_client_hello
				--lua-desync=fake:blob=blob_tls_clienthello_www_onetrust_com:tcp_ts=-600000:repeats=8:strategy=1
				--lua-desync=multisplit:pos=1:seqovl=654:seqovl_pattern=blob_tls_clienthello_www_onetrust_com:strategy=1
				--lua-desync=fake:blob=blob_tls_clienthello_t2_ru:tls_mod=rnd,dupsid,sni=m.ok.ru:badsum:tcp_seq=-10000:strategy=2
				--lua-desync=fake:blob=0x0F0F0F0F:tls_mod=none:badsum:tcp_seq=-10000:strategy=2
				--lua-desync=fakeddisorder:pos=10,midsld:pattern=blob_tls_clienthello_vk_com:seqovl=336:seqovl_pattern=blob_tls_clienthello_gosuslugi_ru:badsum:tcp_seq=-10000:strategy=2
				--lua-desync=fake:blob=fake_default_tls:tcp_seq=10000000:tcp_ack=-66000:repeats=2:tls_mod=rnd,dupsid,sni=fonts.google.com:strategy=3
				--lua-desync=multidisorder:pos=1:seqovl=681:seqovl_pattern=blob_tls_clienthello_www_google_com:strategy=3
				--lua-desync=fake:blob=blob_tls_clienthello_www_google_com:tcp_seq=0:tcp_ack=-66000:badsum:tls_mod=rnd,dupsid,sni=fonts.google.com:strategy=4
				--lua-desync=fake:blob=0x0F0F0F0F:tcp_seq=0:tcp_ack=-66000:badsum:tls_mod=none:strategy=4
				--lua-desync=fakeddisorder:pos=10,midsld:seqovl=336:seqovl_pattern=blob_tls_clienthello_gosuslugi_ru:pattern=blob_tls_clienthello_vk_com:tcp_seq=0:tcp_ack=-66000:badsum:strategy=4
				--lua-desync=fake:blob=blob_tls_clienthello_t2_ru:tcp_seq=0:tcp_ack=-66000:badsum:tls_mod=rnd,dupsid,sni=m.ok.ru:strategy=5
				--lua-desync=fake:blob=0x0F0F0F0F:tcp_seq=0:tcp_ack=-66000:badsum:tls_mod=none:strategy=5
				--lua-desync=fakeddisorder:pos=10,midsld:seqovl=336:seqovl_pattern=blob_tls_clienthello_gosuslugi_ru:pattern=blob_tls_clienthello_vk_com:tcp_seq=0:tcp_ack=-66000:badsum:strategy=5
				--lua-desync=multisplit:pos=1:seqovl=582:seqovl_pattern=blob_tls_clienthello_www_4pda_to:strategy=6
				--lua-desync=fake:blob=blob_tls_clienthello_www_onetrust_com:tcp_seq=0:tcp_ack=-66000:badsum:tls_mod=rnd,dupsid:strategy=7
				--lua-desync=fake:blob=0x0F0F0F0F:tcp_seq=0:tcp_ack=-66000:badsum:tls_mod=none:strategy=7
				--lua-desync=fakeddisorder:pos=10,midsld:pattern=blob_tls_clienthello_vk_com:tcp_seq=0:tcp_ack=-66000:badsum:strategy=7
				--lua-desync=hostfakesplit:midhost=host-2:host=rzd.ru:tcp_seq=0:tcp_ack=-66000:badsum:strategy=8:final				
				
				--new
				--filter-udp=443
				--filter-l7=quic <HOSTLIST_NOAUTO>
				--payload=quic_initial
				--lua-desync=fake:blob=fake_default_quic:repeats=11
			"
			commit $cfgname
		EOF
	fi
	if [ "$strat" = "z2k_autocircular" ]; then
		uci batch <<-EOF
			set $cfgname.config.NFQWS2_PORTS_TCP='80,443'
			set $cfgname.config.NFQWS2_PORTS_UDP='443'
			set $cfgname.config.NFQWS2_OPT="
				--comment=Strategy__$strat
				
				--lua-load=/opt/zapret2/files/lua/z2k-state-persist.lua
				--lua-load=/opt/zapret2/files/lua/z2k-modern-core.lua
				--lua-load=/opt/zapret2/files/lua/z2k-quic-silence.lua
				--lua-load=/opt/zapret2/files/lua/z2k-alert.lua

				--blob=blob_tls_clienthello_www_google_com:@/opt/zapret2/files/fake/tls_clienthello_www_google_com.bin
				--blob=blob_tls_clienthello_vk_com:@/opt/zapret2/files/fake/tls_clienthello_vk_com.bin
				--blob=blob_tls_clienthello_gosuslugi_ru:@/opt/zapret2/files/fake/tls_clienthello_gosuslugi_ru.bin
				--blob=blob_quic_initial_www_google_com:@/opt/zapret2/files/fake/quic_initial_www_google_com.bin

				--filter-tcp=80
				--filter-l7=http <HOSTLIST>
				--payload=http_req
				--lua-desync=fake:blob=fake_default_http:tcp_md5
				--lua-desync=multisplit:pos=method+2

				--new
				--filter-tcp=443
				--filter-l7=tls <HOSTLIST>
				--payload=tls_client_hello
				--lua-desync=circular:fails=2:maxtime=60
				--lua-desync=fake:blob=blob_tls_clienthello_www_google_com:tls_mod=rnd,dupsid,sni=www.google.com:tcp_ts=-1000:strategy=1
				--lua-desync=multidisorder:pos=1,midsld,sniext+1,endhost-2,-10:seqovl=1:seqovl_pattern=blob_tls_clienthello_www_google_com:strategy=1
				--lua-desync=fake:blob=fake_default_tls:ip_ttl=1:tls_mod=rnd,rndsni,padencap:strategy=2
				--lua-desync=multisplit:pos=1,midsld:strategy=2
				--lua-desync=fakeddisorder:pos=10,midsld:seqovl=336:seqovl_pattern=blob_tls_clienthello_gosuslugi_ru:pattern=blob_tls_clienthello_vk_com:strategy=3
				--lua-desync=multisplit:pos=2,endhost:strategy=4

				--new
				--filter-udp=443
				--filter-l7=quic <HOSTLIST_NOAUTO>
				--payload=quic_initial
				--lua-desync=fake:blob=blob_quic_initial_www_google_com:repeats=11
			"
			commit $cfgname
		EOF
	fi
	if [ "$strat" = "youtube_discord_ultimate" ]; then
		uci batch <<-EOF
			set $cfgname.config.NFQWS2_PORTS_TCP='80,443'
			set $cfgname.config.NFQWS2_PORTS_UDP='443,50000-65535'
			set $cfgname.config.NFQWS2_OPT="
				--comment=Strategy__$strat
				
				--blob=blob_quic_initial_www_google_com:@/opt/zapret2/files/fake/quic_initial_www_google_com.bin

				--filter-tcp=80
				--filter-l7=http <HOSTLIST>
				--payload=http_req
				--lua-desync=fake:blob=fake_default_http:tcp_md5
				--lua-desync=multisplit:pos=method+2

				--new
				--filter-tcp=443
				--filter-l7=tls <HOSTLIST>
				--payload=tls_client_hello
				--lua-desync=multisplit:pos=1,midsld:seqovl=1

				--new
				--filter-udp=443
				--filter-l7=quic <HOSTLIST_NOAUTO>
				--payload=quic_initial
				--lua-desync=fake:blob=blob_quic_initial_www_google_com:repeats=11

				--new
				--filter-udp=50000-65535
				--filter-l7=discord
				--out-range=-n1
				--payload=discord_ip_discovery
				--lua-desync=fake:repeats=6
			"
			commit $cfgname
		EOF
	fi
	if [ "$strat" = "flowseal_general" ]; then
		uci batch <<-EOF
			set $cfgname.config.NFQWS2_PORTS_TCP='80,443,2053,2083,2087,2096,8443'
			set $cfgname.config.NFQWS2_PORTS_UDP='443,19294-19344,50000-65535'
			set $cfgname.config.NFQWS2_OPT="
				--comment=Strategy__$strat
				
				--blob=blob_quic_initial_www_google_com:@/opt/zapret2/files/fake/quic_initial_www_google_com.bin

				--filter-tcp=80
				--filter-l7=http <HOSTLIST>
				--payload=http_req
				--lua-desync=fake:blob=fake_default_http:tcp_md5
				--lua-desync=multisplit:pos=method+2

				--new
				--filter-tcp=443,2053,2083,2087,2096,8443
				--filter-l7=tls <HOSTLIST>
				--payload=tls_client_hello
				--lua-desync=multisplit:pos=1,midsld:seqovl=1

				--new
				--filter-udp=443
				--filter-l7=quic <HOSTLIST_NOAUTO>
				--payload=quic_initial
				--lua-desync=fake:blob=blob_quic_initial_www_google_com:repeats=11

				--new
				--filter-udp=19294-19344,50000-65535
				--filter-l7=discord,stun
				--out-range=-n1
				--payload=discord_ip_discovery,stun
				--lua-desync=fake:repeats=6
			"
			commit $cfgname
		EOF
	fi
	if [ "$strat" = "remittor_168" ]; then
		uci batch <<-EOF
			set $cfgname.config.NFQWS2_PORTS_TCP='80,443,853'
			set $cfgname.config.NFQWS2_PORTS_UDP='443,50000-65535'
			set $cfgname.config.NFQWS2_OPT="
				--comment=Strategy__$strat
				
				--blob=blob_tls_clienthello_www_google_com:@/opt/zapret2/files/fake/tls_clienthello_www_google_com.bin
				--blob=blob_quic_initial_www_google_com:@/opt/zapret2/files/fake/quic_initial_www_google_com.bin

				--filter-tcp=80
				--filter-l7=http <HOSTLIST>
				--payload=http_req
				--lua-desync=fake:blob=fake_default_http:tcp_md5
				--lua-desync=multisplit:pos=method+2

				--new
				--filter-tcp=443
				--filter-l7=tls <HOSTLIST>
				--payload=tls_client_hello
				--lua-desync=fake:blob=blob_tls_clienthello_www_google_com:tls_mod=rnd,dupsid,sni=www.google.com:tcp_ts=-1000
				--lua-desync=multidisorder:pos=1,midsld,sniext+1,endhost-2,-10:seqovl=1:seqovl_pattern=blob_tls_clienthello_www_google_com:tcp_ts_up

				--new
				--filter-tcp=853
				--lua-desync=multisplit:seqovl=8:seqovl_pattern=0x000100502112A442

				--new
				--filter-udp=443
				--filter-l7=quic <HOSTLIST_NOAUTO>
				--payload=quic_initial
				--lua-desync=fake:blob=blob_quic_initial_www_google_com:repeats=11

				--new
				--filter-udp=50000-65535
				--filter-l7=discord
				--out-range=-n1
				--payload=discord_ip_discovery
				--lua-desync=fake:repeats=6
			"
			commit $cfgname
		EOF
	fi
	if [ "$strat" = "flowseal_fake_tls_auto" ]; then
		uci batch <<-EOF
			set $cfgname.config.NFQWS2_PORTS_TCP='80,443,2053,2083,2087,2096,8443'
			set $cfgname.config.NFQWS2_PORTS_UDP='443,19294-19344,50000-65535'
			set $cfgname.config.NFQWS2_OPT="
				--comment=Strategy__$strat
				
				--blob=blob_tls_clienthello_www_google_com:@/opt/zapret2/files/fake/tls_clienthello_www_google_com.bin
				--blob=blob_quic_initial_www_google_com:@/opt/zapret2/files/fake/quic_initial_www_google_com.bin
				--blob=blob_tls_clienthello_max_ru:@/opt/zapret2/files/fake/tls_clienthello_max_ru.bin

				--filter-tcp=80
				--filter-l7=http <HOSTLIST>
				--payload=http_req
				--lua-desync=fake:blob=fake_default_http:tcp_md5
				--lua-desync=multisplit:pos=method+2

				--new
				--filter-tcp=443,2053,2083,2087,2096,8443
				--filter-l7=tls <HOSTLIST>
				--payload=tls_client_hello
				--lua-desync=fake:blob=blob_tls_clienthello_www_google_com:tls_mod=rnd,dupsid,sni=www.google.com:tcp_seq=-10000:badsum
				--lua-desync=multidisorder:pos=1,midsld

				--new
				--filter-udp=443
				--filter-l7=quic <HOSTLIST_NOAUTO>
				--payload=quic_initial
				--lua-desync=fake:blob=blob_quic_initial_www_google_com:repeats=11

				--new
				--filter-udp=19294-19344,50000-65535
				--filter-l7=discord,stun
				--out-range=-n1
				--payload=discord_ip_discovery,stun
				--lua-desync=fake:repeats=6
			"
			commit $cfgname
		EOF
	fi
	if [ "$strat" = "flowseal_simple_fake" ]; then
		uci batch <<-EOF
			set $cfgname.config.NFQWS2_PORTS_TCP='80,443,2053,2083,2087,2096,8443'
			set $cfgname.config.NFQWS2_PORTS_UDP='443,19294-19344,50000-65535'
			set $cfgname.config.NFQWS2_OPT="
				--comment=Strategy__$strat
				
				--blob=blob_tls_clienthello_www_google_com:@/opt/zapret2/files/fake/tls_clienthello_www_google_com.bin
				--blob=blob_quic_initial_www_google_com:@/opt/zapret2/files/fake/quic_initial_www_google_com.bin

				--filter-tcp=80
				--filter-l7=http <HOSTLIST>
				--payload=http_req
				--lua-desync=fake:blob=fake_default_http:tcp_md5
				--lua-desync=multisplit:pos=method+2

				--new
				--filter-tcp=443,2053,2083,2087,2096,8443
				--filter-l7=tls <HOSTLIST>
				--payload=tls_client_hello
				--lua-desync=fake:blob=blob_tls_clienthello_www_google_com:tcp_ts=-1000:repeats=6

				--new
				--filter-udp=443
				--filter-l7=quic <HOSTLIST_NOAUTO>
				--payload=quic_initial
				--lua-desync=fake:blob=blob_quic_initial_www_google_com:repeats=6

				--new
				--filter-udp=19294-19344,50000-65535
				--filter-l7=discord,stun
				--out-range=-n1
				--payload=discord_ip_discovery,stun
				--lua-desync=fake:repeats=6
			"
			commit $cfgname
		EOF
	fi
	if [ "$strat" = "z2_ready_01" -o "$strat" = "z2-ready-01" ]; then
		uci batch <<-EOF
			set $cfgname.config.NFQWS2_PORTS_TCP='80,443'
			set $cfgname.config.NFQWS2_PORTS_UDP='443,50000-65535'
			set $cfgname.config.NFQWS2_OPT="
				--comment=Strategy__$strat
				--filter-tcp=80 --filter-l7=http <HOSTLIST> --payload=http_req --lua-desync=fake:blob=fake_default_http:tcp_md5 --lua-desync=multisplit:pos=method+2
				--new --filter-tcp=443 --filter-l7=tls <HOSTLIST> --payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:tcp_md5:tcp_seq=-10000 --lua-desync=multidisorder:pos=1,midsld
				--new --filter-udp=443 --filter-l7=quic <HOSTLIST_NOAUTO> --payload=quic_initial --lua-desync=fake:blob=fake_default_quic:repeats=6
				--new --filter-udp=50000-65535 --filter-l7=discord --out-range=-n1 --payload=discord_ip_discovery --lua-desync=fake:repeats=6
			"
			commit $cfgname
		EOF
	fi
	if [ "$strat" = "z2_ready_02" -o "$strat" = "z2-ready-02" ]; then
		uci batch <<-EOF
			set $cfgname.config.NFQWS2_PORTS_TCP='80,443'
			set $cfgname.config.NFQWS2_PORTS_UDP='443,50000-65535'
			set $cfgname.config.NFQWS2_OPT="
				--comment=Strategy__$strat
				--filter-tcp=80 --filter-l7=http <HOSTLIST> --payload=http_req --lua-desync=fake:blob=fake_default_http:tcp_md5 --lua-desync=multisplit:pos=method+2
				--new --filter-tcp=443 --filter-l7=tls <HOSTLIST> --payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:tcp_md5:repeats=11:tls_mod=rnd,dupsid,sni=www.google.com --lua-desync=multidisorder:pos=1,midsld
				--new --filter-udp=443 --filter-l7=quic <HOSTLIST_NOAUTO> --payload=quic_initial --lua-desync=fake:blob=fake_default_quic:repeats=11
				--new --filter-udp=50000-65535 --filter-l7=discord --out-range=-n1 --payload=discord_ip_discovery --lua-desync=fake:repeats=6
			"
			commit $cfgname
		EOF
	fi
	if [ "$strat" = "z2_ready_03" -o "$strat" = "z2-ready-03" ]; then
		uci batch <<-EOF
			set $cfgname.config.NFQWS2_PORTS_TCP='80,443'
			set $cfgname.config.NFQWS2_PORTS_UDP='443,50000-65535'
			set $cfgname.config.NFQWS2_OPT="
				--comment=Strategy__$strat
				--filter-tcp=80 --filter-l7=http <HOSTLIST> --payload=http_req --lua-desync=fake:blob=fake_default_http:tcp_md5 --lua-desync=multisplit:pos=method+2
				--new --filter-tcp=443 --filter-l7=tls <HOSTLIST> --payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:tcp_ts=-1000:repeats=6 --lua-desync=multisplit:pos=1,midsld
				--new --filter-udp=443 --filter-l7=quic <HOSTLIST_NOAUTO> --payload=quic_initial --lua-desync=send:ipfrag --lua-desync=drop
				--new --filter-udp=50000-65535 --filter-l7=discord --out-range=-n1 --payload=discord_ip_discovery --lua-desync=fake:repeats=6
			"
			commit $cfgname
		EOF
	fi
	if [ "$strat" = "z2_ready_04" -o "$strat" = "z2-ready-04" ]; then
		uci batch <<-EOF
			set $cfgname.config.NFQWS2_PORTS_TCP='80,443'
			set $cfgname.config.NFQWS2_PORTS_UDP='443,50000-65535'
			set $cfgname.config.NFQWS2_OPT="
				--comment=Strategy__$strat
				--filter-tcp=80 --filter-l7=http <HOSTLIST> --payload=http_req --lua-desync=fake:blob=fake_default_http:tcp_md5 --lua-desync=multisplit:pos=method+2
				--new --filter-tcp=443 --filter-l7=tls <HOSTLIST> --payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:tcp_md5:repeats=6 --lua-desync=multisplit:pos=2,midsld
				--new --filter-udp=443 --filter-l7=quic <HOSTLIST_NOAUTO> --payload=quic_initial --lua-desync=fake:blob=fake_default_quic:repeats=6
				--new --filter-udp=50000-65535 --filter-l7=discord --out-range=-n1 --payload=discord_ip_discovery --lua-desync=fake:repeats=6
			"
			commit $cfgname
		EOF
	fi
	if [ "$strat" = "z2_ready_05" -o "$strat" = "z2-ready-05" ]; then
		uci batch <<-EOF
			set $cfgname.config.NFQWS2_PORTS_TCP='80,443'
			set $cfgname.config.NFQWS2_PORTS_UDP='443,50000-65535'
			set $cfgname.config.NFQWS2_OPT="
				--comment=Strategy__$strat
				--filter-tcp=80 --filter-l7=http <HOSTLIST> --payload=http_req --lua-desync=fake:blob=fake_default_http:tcp_md5 --lua-desync=multisplit:pos=method+2
				--new --filter-tcp=443 --filter-l7=tls <HOSTLIST> --payload=tls_client_hello --lua-desync=multisplit:pos=1,midsld:seqovl=1
				--new --filter-udp=443 --filter-l7=quic <HOSTLIST_NOAUTO> --payload=quic_initial --lua-desync=fake:blob=fake_default_quic:repeats=11
				--new --filter-udp=50000-65535 --filter-l7=discord --out-range=-n1 --payload=discord_ip_discovery --lua-desync=fake:repeats=6
			"
			commit $cfgname
		EOF
	fi
	if [ "$strat" = "z2_ready_06" -o "$strat" = "z2-ready-06" ]; then
		uci batch <<-EOF
			set $cfgname.config.NFQWS2_PORTS_TCP='80,443'
			set $cfgname.config.NFQWS2_PORTS_UDP='443,50000-65535'
			set $cfgname.config.NFQWS2_OPT="
				--comment=Strategy__$strat
				--filter-tcp=80 --filter-l7=http <HOSTLIST> --payload=http_req --lua-desync=fake:blob=fake_default_http:tcp_md5 --lua-desync=multisplit:pos=method+2
				--new --filter-tcp=443 --filter-l7=tls <HOSTLIST> --payload=tls_client_hello --lua-desync=multidisorder:pos=1,sniext+1,host+1,midsld-2,midsld,midsld+2,endhost-1
				--new --filter-udp=443 --filter-l7=quic <HOSTLIST_NOAUTO> --payload=quic_initial --lua-desync=send:ipfrag --lua-desync=drop
				--new --filter-udp=50000-65535 --filter-l7=discord --out-range=-n1 --payload=discord_ip_discovery --lua-desync=fake:repeats=6
			"
			commit $cfgname
		EOF
	fi
	if [ "$strat" = "z2_ready_07" -o "$strat" = "z2-ready-07" ]; then
		uci batch <<-EOF
			set $cfgname.config.NFQWS2_PORTS_TCP='80,443'
			set $cfgname.config.NFQWS2_PORTS_UDP='443,50000-65535'
			set $cfgname.config.NFQWS2_OPT="
				--comment=Strategy__$strat
				--filter-tcp=80 --filter-l7=http <HOSTLIST> --payload=http_req --lua-desync=fake:blob=fake_default_http:tcp_md5 --lua-desync=multisplit:pos=method+2
				--new --filter-tcp=443 --filter-l7=tls <HOSTLIST> --payload=tls_client_hello --lua-desync=tcpseg:pos=0,-1:seqovl=1 --lua-desync=drop
				--new --filter-udp=443 --filter-l7=quic <HOSTLIST_NOAUTO> --payload=quic_initial --lua-desync=fake:blob=fake_default_quic:repeats=11
				--new --filter-udp=50000-65535 --filter-l7=discord --out-range=-n1 --payload=discord_ip_discovery --lua-desync=fake:repeats=6
			"
			commit $cfgname
		EOF
	fi
	if [ "$strat" = "z2_ready_08" -o "$strat" = "z2-ready-08" ]; then
		uci batch <<-EOF
			set $cfgname.config.NFQWS2_PORTS_TCP='80,443'
			set $cfgname.config.NFQWS2_PORTS_UDP='443,50000-65535'
			set $cfgname.config.NFQWS2_OPT="
				--comment=Strategy__$strat
				--filter-tcp=80 --filter-l7=http <HOSTLIST> --payload=http_req --lua-desync=fake:blob=fake_default_http:tcp_md5 --lua-desync=multisplit:pos=method+2
				--new --filter-tcp=443 --filter-l7=tls <HOSTLIST> --payload=tls_client_hello --lua-desync=wssize:wsize=1:scale=6 --lua-desync=multidisorder:pos=1,midsld
				--new --filter-udp=443 --filter-l7=quic <HOSTLIST_NOAUTO> --payload=quic_initial --lua-desync=fake:blob=fake_default_quic:repeats=6
				--new --filter-udp=50000-65535 --filter-l7=discord --out-range=-n1 --payload=discord_ip_discovery --lua-desync=fake:repeats=6
			"
			commit $cfgname
		EOF
	fi
	if [ "$strat" = "z2_ready_09" -o "$strat" = "z2-ready-09" ]; then
		uci batch <<-EOF
			set $cfgname.config.NFQWS2_PORTS_TCP='80,443'
			set $cfgname.config.NFQWS2_PORTS_UDP='443,50000-65535'
			set $cfgname.config.NFQWS2_OPT="
				--comment=Strategy__$strat
				--filter-tcp=80 --filter-l7=http <HOSTLIST> --payload=http_req --lua-desync=fake:blob=fake_default_http:tcp_md5 --lua-desync=multisplit:pos=method+2
				--new --filter-tcp=443 --filter-l7=tls <HOSTLIST> --payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:tcp_md5:repeats=11:tls_mod=rnd,dupsid --lua-desync=multisplit:pos=2,midsld
				--new --filter-udp=443 --filter-l7=quic <HOSTLIST_NOAUTO> --payload=quic_initial --lua-desync=fake:blob=fake_default_quic:repeats=11
				--new --filter-udp=50000-65535 --filter-l7=discord --out-range=-n1 --payload=discord_ip_discovery --lua-desync=fake:repeats=6
			"
			commit $cfgname
		EOF
	fi
	if [ "$strat" = "z2_ready_10" -o "$strat" = "z2-ready-10" ]; then
		uci batch <<-EOF
			set $cfgname.config.NFQWS2_PORTS_TCP='80,443'
			set $cfgname.config.NFQWS2_PORTS_UDP='443,50000-65535'
			set $cfgname.config.NFQWS2_OPT="
				--comment=Strategy__$strat
				--filter-tcp=80 --filter-l7=http <HOSTLIST> --payload=http_req --lua-desync=fake:blob=fake_default_http:tcp_md5 --lua-desync=multisplit:pos=method+2
				--new --filter-tcp=443 --filter-l7=tls <HOSTLIST> --payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:tcp_ts=-1000:repeats=6 --lua-desync=multidisorder:pos=midsld
				--new --filter-udp=443 --filter-l7=quic <HOSTLIST_NOAUTO> --payload=quic_initial --lua-desync=send:ipfrag --lua-desync=drop
				--new --filter-udp=50000-65535 --filter-l7=discord --out-range=-n1 --payload=discord_ip_discovery --lua-desync=fake:repeats=6
			"
			commit $cfgname
		EOF
	fi
	if [ "$strat" = "zm_games" ]; then
		uci batch <<-EOF
			set $cfgname.config.NFQWS2_PORTS_TCP='80,443,2802,2302,2502,3478-3480,3724,6000-8000,8085,8090,8100,8903,8904,25565,27015-27030,27036-27037,35500-35600,50001,60442'
			set $cfgname.config.NFQWS2_PORTS_UDP='88,443,1024-2407,2409-4499,4502-19293,19345-49999,50000-65535'
			set $cfgname.config.NFQWS2_OPT="
				--comment=Strategy__$strat
				--filter-tcp=80 --filter-l7=http <HOSTLIST> --payload=http_req --lua-desync=fake:blob=fake_default_http:tcp_md5 --lua-desync=multisplit:pos=method+2
				--new --filter-tcp=443 --filter-l7=tls <HOSTLIST> --payload=tls_client_hello --lua-desync=multisplit:pos=1,midsld:seqovl=1
				--new --filter-udp=443 --filter-l7=quic <HOSTLIST_NOAUTO> --payload=quic_initial --lua-desync=fake:blob=fake_default_quic:repeats=11
				--new --filter-udp=88,1024-2407,2409-4499,4502-19293,19345-49999,50000-65535 --out-range=<n4 --payload=known,unknown --lua-desync=fake:blob=blob_quic_initial_4pda_to:repeats=10
				--new --filter-tcp=2802,2302,2502,3478-3480,3724,6000-8000,8085,8090,8100,8903,8904,25565,27015-27030,27036-27037,35500-35600,50001,60442 --out-range=<n4 --payload=known,unknown --lua-desync=multisplit:pos=1:seqovl=582
			"
			commit $cfgname
		EOF
	fi
	if [ "$strat" = "zm_discord_media" ]; then
		uci batch <<-EOF
			set $cfgname.config.NFQWS2_PORTS_TCP='80,443,2053,2083,2087,2096,8443'
			set $cfgname.config.NFQWS2_PORTS_UDP='443,19294-19344,50000-65535'
			set $cfgname.config.NFQWS2_OPT="
				--comment=Strategy__$strat
				--filter-tcp=80 --filter-l7=http <HOSTLIST> --payload=http_req --lua-desync=fake:blob=fake_default_http:tcp_md5 --lua-desync=multisplit:pos=method+2
				--new --filter-tcp=443 --filter-l7=tls <HOSTLIST> --payload=tls_client_hello --lua-desync=multisplit:pos=1,midsld:seqovl=1
				--new --filter-tcp=2053,2083,2087,2096,8443 --filter-l7=tls --payload=tls_client_hello --lua-desync=fake:blob=blob_tls_clienthello_www_google_com:repeats=8:tcp_ts=-600000 --lua-desync=multisplit:pos=1:seqovl=681:seqovl_pattern=blob_tls_clienthello_www_google_com:repeats=8
				--new --filter-udp=443 --filter-l7=quic <HOSTLIST_NOAUTO> --payload=quic_initial --lua-desync=fake:blob=fake_default_quic:repeats=11
				--new --filter-udp=19294-19344,50000-65535 --filter-l7=discord,stun --out-range=-n1 --payload=discord_ip_discovery,stun --lua-desync=fake:repeats=6
			"
			commit $cfgname
		EOF
	fi
	if [ "$strat" = "zm_yv01" ]; then
		uci batch <<-EOF
			set $cfgname.config.NFQWS2_PORTS_TCP='80,443'
			set $cfgname.config.NFQWS2_PORTS_UDP='443,50000-65535'
			set $cfgname.config.NFQWS2_OPT="
				--comment=Strategy__$strat
				--filter-tcp=80 --filter-l7=http <HOSTLIST> --payload=http_req --lua-desync=fake:blob=fake_default_http:tcp_md5 --lua-desync=multisplit:pos=method+2
				--new --filter-tcp=443 --filter-l7=tls <HOSTLIST> --payload=tls_client_hello --ip-id=zero --lua-desync=multisplit:pos=1:seqovl=681:seqovl_pattern=blob_tls_clienthello_www_google_com
				--new --filter-udp=443 --filter-l7=quic <HOSTLIST_NOAUTO> --payload=quic_initial --lua-desync=fake:blob=fake_default_quic:repeats=11
				--new --filter-udp=50000-65535 --filter-l7=discord --out-range=-n1 --payload=discord_ip_discovery --lua-desync=fake:repeats=6
			"
			commit $cfgname
		EOF
	fi
	if [ "$strat" = "zm_yv02" ]; then
		uci batch <<-EOF
			set $cfgname.config.NFQWS2_PORTS_TCP='80,443'
			set $cfgname.config.NFQWS2_PORTS_UDP='443,50000-65535'
			set $cfgname.config.NFQWS2_OPT="
				--comment=Strategy__$strat
				--filter-tcp=80 --filter-l7=http <HOSTLIST> --payload=http_req --lua-desync=fake:blob=fake_default_http:tcp_md5 --lua-desync=multisplit:pos=method+2
				--new --filter-tcp=443 --filter-l7=tls <HOSTLIST> --payload=tls_client_hello --lua-desync=multisplit:pos=1,sniext+1:seqovl=1
				--new --filter-udp=443 --filter-l7=quic <HOSTLIST_NOAUTO> --payload=quic_initial --lua-desync=fake:blob=fake_default_quic:repeats=11
				--new --filter-udp=50000-65535 --filter-l7=discord --out-range=-n1 --payload=discord_ip_discovery --lua-desync=fake:repeats=6
			"
			commit $cfgname
		EOF
	fi
	if [ "$strat" = "zm_yv03" ]; then
		uci batch <<-EOF
			set $cfgname.config.NFQWS2_PORTS_TCP='80,443'
			set $cfgname.config.NFQWS2_PORTS_UDP='443,50000-65535'
			set $cfgname.config.NFQWS2_OPT="
				--comment=Strategy__$strat
				--filter-tcp=80 --filter-l7=http <HOSTLIST> --payload=http_req --lua-desync=fake:blob=fake_default_http:tcp_md5 --lua-desync=multisplit:pos=method+2
				--new --filter-tcp=443 --filter-l7=tls <HOSTLIST> --payload=tls_client_hello --lua-desync=fake:blob=0x0F0F0F0F:badsum:tcp_seq=-10000 --lua-desync=multisplit:pos=2,sld:seqovl=620:seqovl_pattern=blob_tls_clienthello_www_google_com
				--new --filter-udp=443 --filter-l7=quic <HOSTLIST_NOAUTO> --payload=quic_initial --lua-desync=fake:blob=fake_default_quic:repeats=11
				--new --filter-udp=50000-65535 --filter-l7=discord --out-range=-n1 --payload=discord_ip_discovery --lua-desync=fake:repeats=6
			"
			commit $cfgname
		EOF
	fi
	if [ "$strat" = "zm_yv08" ]; then
		uci batch <<-EOF
			set $cfgname.config.NFQWS2_PORTS_TCP='80,443'
			set $cfgname.config.NFQWS2_PORTS_UDP='443,50000-65535'
			set $cfgname.config.NFQWS2_OPT="
				--comment=Strategy__$strat
				--filter-tcp=80 --filter-l7=http <HOSTLIST> --payload=http_req --lua-desync=fake:blob=fake_default_http:tcp_md5 --lua-desync=multisplit:pos=method+2
				--new --filter-tcp=443 --filter-l7=tls <HOSTLIST> --payload=tls_client_hello --lua-desync=hostfakesplit:host=google.com:tcp_ts=-600000
				--new --filter-udp=443 --filter-l7=quic <HOSTLIST_NOAUTO> --payload=quic_initial --lua-desync=fake:blob=fake_default_quic:repeats=11
				--new --filter-udp=50000-65535 --filter-l7=discord --out-range=-n1 --payload=discord_ip_discovery --lua-desync=fake:repeats=6
			"
			commit $cfgname
		EOF
	fi
	if [ "$strat" = "zm_yv16" ]; then
		uci batch <<-EOF
			set $cfgname.config.NFQWS2_PORTS_TCP='80,443'
			set $cfgname.config.NFQWS2_PORTS_UDP='443,50000-65535'
			set $cfgname.config.NFQWS2_OPT="
				--comment=Strategy__$strat
				--filter-tcp=80 --filter-l7=http <HOSTLIST> --payload=http_req --lua-desync=fake:blob=fake_default_http:tcp_md5 --lua-desync=multisplit:pos=method+2
				--new --filter-tcp=443 --filter-l7=tls <HOSTLIST> --payload=tls_client_hello --lua-desync=multisplit:pos=1,sniext+1:seqovl=1:badsum
				--new --filter-udp=443 --filter-l7=quic <HOSTLIST_NOAUTO> --payload=quic_initial --lua-desync=fake:blob=fake_default_quic:repeats=11
				--new --filter-udp=50000-65535 --filter-l7=discord --out-range=-n1 --payload=discord_ip_discovery --lua-desync=fake:repeats=6
			"
			commit $cfgname
		EOF
	fi
	if [ "$strat" = "zm_yv24" ]; then
		uci batch <<-EOF
			set $cfgname.config.NFQWS2_PORTS_TCP='80,443'
			set $cfgname.config.NFQWS2_PORTS_UDP='443,50000-65535'
			set $cfgname.config.NFQWS2_OPT="
				--comment=Strategy__$strat
				--filter-tcp=80 --filter-l7=http <HOSTLIST> --payload=http_req --lua-desync=fake:blob=fake_default_http:tcp_md5 --lua-desync=multisplit:pos=method+2
				--new --filter-tcp=443 --filter-l7=tls <HOSTLIST> --payload=tls_client_hello --lua-desync=fake:blob=blob_stun:tcp_seq=-10000:badsum:repeats=8 --lua-desync=multisplit:pos=1:seqovl=654:seqovl_pattern=blob_stun
				--new --filter-udp=443 --filter-l7=quic <HOSTLIST_NOAUTO> --payload=quic_initial --lua-desync=fake:blob=fake_default_quic:repeats=11
				--new --filter-udp=50000-65535 --filter-l7=discord --out-range=-n1 --payload=discord_ip_discovery --lua-desync=fake:repeats=6
			"
			commit $cfgname
		EOF
	fi
	if [ "$strat" = "zm_krushaaa" ]; then
		uci batch <<-EOF
			set $cfgname.config.MODE_FILTER='hostlist'
			set $cfgname.config.NFQWS2_PORTS_TCP='80,443,2053,2083,2087,2096,8443'
			set $cfgname.config.NFQWS2_PORTS_UDP='443,19294-19344,50000-50100'
			set $cfgname.config.NFQWS2_OPT="
				--comment=Strategy__zm_krushaaa
				--blob=quic_steam:@/opt/zapret2/files/fake/quic_initial_steamcommunity_com.bin
				--blob=quic_lol:@/opt/zapret2/files/fake/quic_initial_leagueoflegends.com.bin
				--blob=tls_burger:@/opt/zapret2/files/fake/tls_burgerkingrus_ru.bin
				--blob=tls_magnit:@/opt/zapret2/files/fake/tls_magnit.bin
				--blob=stun2_fake:@/opt/zapret2/files/fake/stun2.bin
				--blob=discord_udp:@/opt/zapret2/files/fake/ACTIVE_DISCORD_UDP.bin
				--blob=game_udp:@/opt/zapret2/files/fake/ACTIVE_GAME_UDP.bin
				--filter-tcp=2053,2083,2087,2096,8443 --filter-l7=tls --hostlist-domains=discord.media --payload=tls_client_hello --lua-desync=fake:blob=tls_magnit:repeats=4:tcp_ts=-600000:tcp_ts_up --lua-desync=hostfakesplit:host=mail.ru:tcp_ts=-600000:tcp_ts_up
				--new
				--filter-tcp=443 --filter-l7=tls --hostlist=/opt/zapret2/ipset/zapret-hosts-google.txt --payload=tls_client_hello --lua-desync=hostfakesplit:host=www.microsoft.com:ip_id=zero:tcp_ts=-600000:tcp_ts_up
				--new
				--filter-tcp=80,443 --filter-l7=http,tls <HOSTLIST> --payload=tls_client_hello --lua-desync=fake:blob=stun2_fake:repeats=4:tcp_ts=-600000:tcp_ts_up --lua-desync=fake:blob=tls_burger:repeats=4:tcp_ts=-600000:tcp_ts_up --payload=http_req --lua-desync=fake:blob=tls_burger:repeats=4:tcp_ts=-600000:tcp_ts_up
				--new
				--filter-udp=443 --filter-l7=quic <HOSTLIST_NOAUTO> --payload=quic_initial --lua-desync=fake:blob=quic_lol:repeats=4
				--new
				--filter-udp=19294-19344,50000-50100 --filter-l7=discord,stun,unknown --payload=discord_ip_discovery,stun --lua-desync=fake:blob=quic_steam:repeats=4 --lua-desync=fake:blob=discord_udp:repeats=4 --payload=unknown --lua-desync=fake:blob=quic_steam:payload=unknown:repeats=4 --lua-desync=fake:blob=discord_udp:payload=unknown:repeats=4
			"
			commit $cfgname
		EOF
	fi
	if [ "$strat" = "zm_alt" ]; then
		uci batch <<-EOF
			set $cfgname.config.MODE_FILTER='hostlist'
			set $cfgname.config.NFQWS2_PORTS_TCP='80,443,2053,2083,2087,2096,8443'
			set $cfgname.config.NFQWS2_PORTS_UDP='443,19294-19344,50000-50100'
			set $cfgname.config.NFQWS2_OPT="
				--comment=Strategy__zm_alt
				--blob=quic_google:@/opt/zapret2/files/fake/quic_initial_www_google_com.bin
				--blob=tls_google:@/opt/zapret2/files/fake/tls_clienthello_www_google_com.bin
				--blob=tls_max:@/opt/zapret2/files/fake/tls_clienthello_max_ru.bin
				--blob=stun_fake:@/opt/zapret2/files/fake/stun.bin
				--blob=discord_udp:@/opt/zapret2/files/fake/ACTIVE_DISCORD_UDP.bin
				--blob=game_udp:@/opt/zapret2/files/fake/ACTIVE_GAME_UDP.bin
				--filter-tcp=2053,2083,2087,2096,8443 --filter-l7=tls --hostlist-domains=discord.media --payload=tls_client_hello --lua-desync=fake:blob=tls_google:repeats=6:tcp_ts=-600000:tcp_ts_up --lua-desync=fakedsplit:pattern=0x00:repeats=6:tcp_ts=-600000:tcp_ts_up
				--new
				--filter-tcp=443 --filter-l7=tls --hostlist=/opt/zapret2/ipset/zapret-hosts-google.txt --payload=tls_client_hello --lua-desync=fake:blob=tls_google:repeats=6:ip_id=zero:tcp_ts=-600000:tcp_ts_up --lua-desync=fakedsplit:pattern=0x00:repeats=6:ip_id=zero:tcp_ts=-600000:tcp_ts_up
				--new
				--filter-tcp=80,443 --filter-l7=http,tls <HOSTLIST> --payload=tls_client_hello --lua-desync=fake:blob=stun_fake:repeats=6:tcp_ts=-600000:tcp_ts_up --lua-desync=fake:blob=tls_google:repeats=6:tcp_ts=-600000:tcp_ts_up --lua-desync=fakedsplit:pattern=0x00:repeats=6:tcp_ts=-600000:tcp_ts_up --payload=http_req --lua-desync=fake:blob=tls_max:repeats=6:tcp_ts=-600000:tcp_ts_up --lua-desync=fakedsplit:pattern=0x00:repeats=6:tcp_ts=-600000:tcp_ts_up
				--new
				--filter-udp=443 --filter-l7=quic <HOSTLIST_NOAUTO> --payload=quic_initial --lua-desync=fake:blob=quic_google:repeats=6
				--new
				--filter-udp=19294-19344,50000-50100 --filter-l7=discord,stun --payload=discord_ip_discovery,stun --lua-desync=fake:blob=discord_udp:repeats=6
			"
			commit $cfgname
		EOF
	fi
	if [ "$strat" = "zm_alt2" ]; then
		uci batch <<-EOF
			set $cfgname.config.MODE_FILTER='hostlist'
			set $cfgname.config.NFQWS2_PORTS_TCP='80,443,2053,2083,2087,2096,8443'
			set $cfgname.config.NFQWS2_PORTS_UDP='443,19294-19344,50000-50100'
			set $cfgname.config.NFQWS2_OPT="
				--comment=Strategy__zm_alt2
				--blob=quic_google:@/opt/zapret2/files/fake/quic_initial_www_google_com.bin
				--blob=tls_google:@/opt/zapret2/files/fake/tls_clienthello_www_google_com.bin
				--blob=discord_udp:@/opt/zapret2/files/fake/ACTIVE_DISCORD_UDP.bin
				--blob=game_udp:@/opt/zapret2/files/fake/ACTIVE_GAME_UDP.bin
				--filter-tcp=2053,2083,2087,2096,8443 --filter-l7=tls --hostlist-domains=discord.media --payload=tls_client_hello --lua-desync=multisplit:pos=2:seqovl=652:seqovl_pattern=tls_google
				--new
				--filter-tcp=443 --filter-l7=tls --hostlist=/opt/zapret2/ipset/zapret-hosts-google.txt --payload=tls_client_hello --lua-desync=multisplit:pos=2:seqovl=652:seqovl_pattern=tls_google:ip_id=zero
				--new
				--filter-tcp=80,443 --filter-l7=http,tls <HOSTLIST> --payload=tls_client_hello --lua-desync=multisplit:pos=2:seqovl=652:seqovl_pattern=tls_google --payload=http_req --lua-desync=multisplit:pos=2:seqovl=652:seqovl_pattern=tls_google
				--new
				--filter-udp=443 --filter-l7=quic <HOSTLIST_NOAUTO> --payload=quic_initial --lua-desync=fake:blob=quic_google:repeats=6
				--new
				--filter-udp=19294-19344,50000-50100 --filter-l7=discord,stun --payload=discord_ip_discovery,stun --lua-desync=fake:blob=discord_udp:repeats=6
			"
			commit $cfgname
		EOF
	fi
	if [ "$strat" = "zm_alt3" ]; then
		uci batch <<-EOF
			set $cfgname.config.MODE_FILTER='hostlist'
			set $cfgname.config.NFQWS2_PORTS_TCP='80,443,2053,2083,2087,2096,8443'
			set $cfgname.config.NFQWS2_PORTS_UDP='443,19294-19344,50000-50100'
			set $cfgname.config.NFQWS2_OPT="
				--comment=Strategy__zm_alt3
				--blob=quic_google:@/opt/zapret2/files/fake/quic_initial_www_google_com.bin
				--blob=tls_max:@/opt/zapret2/files/fake/tls_clienthello_max_ru.bin
				--blob=discord_udp:@/opt/zapret2/files/fake/ACTIVE_DISCORD_UDP.bin
				--blob=game_udp:@/opt/zapret2/files/fake/ACTIVE_GAME_UDP.bin
				--filter-tcp=2053,2083,2087,2096,8443 --filter-l7=tls --hostlist-domains=discord.media --payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:tls_mod=rnd,dupsid,sni=www.google.com:tcp_ts=-600000:tcp_ts_up --lua-desync=hostfakesplit:host=www.google.com:tcp_ts=-600000:tcp_ts_up
				--new
				--filter-tcp=443 --filter-l7=tls --hostlist=/opt/zapret2/ipset/zapret-hosts-google.txt --payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:tls_mod=rnd,dupsid,sni=www.google.com:ip_id=zero:tcp_ts=-600000:tcp_ts_up --lua-desync=hostfakesplit:host=www.google.com:ip_id=zero:tcp_ts=-600000:tcp_ts_up
				--new
				--filter-tcp=80,443 --filter-l7=http,tls <HOSTLIST> --payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:tls_mod=rnd,dupsid,sni=ya.ru:tcp_ts=-600000:tcp_ts_up --lua-desync=hostfakesplit:host=ya.ru:tcp_ts=-600000:tcp_ts_up --payload=http_req --lua-desync=fake:blob=tls_max:tcp_ts=-600000:tcp_ts_up --lua-desync=hostfakesplit:host=ya.ru:tcp_ts=-600000:tcp_ts_up
				--new
				--filter-udp=443 --filter-l7=quic <HOSTLIST_NOAUTO> --payload=quic_initial --lua-desync=fake:blob=quic_google:repeats=6
				--new
				--filter-udp=19294-19344,50000-50100 --filter-l7=discord,stun --payload=discord_ip_discovery,stun --lua-desync=fake:blob=discord_udp:repeats=6
			"
			commit $cfgname
		EOF
	fi
	if [ "$strat" = "zm_alt4" ]; then
		uci batch <<-EOF
			set $cfgname.config.MODE_FILTER='hostlist'
			set $cfgname.config.NFQWS2_PORTS_TCP='80,443,2053,2083,2087,2096,8443'
			set $cfgname.config.NFQWS2_PORTS_UDP='443,19294-19344,50000-50100'
			set $cfgname.config.NFQWS2_OPT="
				--comment=Strategy__zm_alt4
				--blob=quic_google:@/opt/zapret2/files/fake/quic_initial_www_google_com.bin
				--blob=tls_google:@/opt/zapret2/files/fake/tls_clienthello_www_google_com.bin
				--blob=tls_max:@/opt/zapret2/files/fake/tls_clienthello_max_ru.bin
				--blob=stun_fake:@/opt/zapret2/files/fake/stun.bin
				--blob=discord_udp:@/opt/zapret2/files/fake/ACTIVE_DISCORD_UDP.bin
				--blob=game_udp:@/opt/zapret2/files/fake/ACTIVE_GAME_UDP.bin
				--filter-tcp=2053,2083,2087,2096,8443 --filter-l7=tls --hostlist-domains=discord.media --payload=tls_client_hello --lua-desync=fake:blob=tls_google:repeats=6:tcp_seq=1000:tcp_ack=-66000:tcp_ts_up --lua-desync=multisplit
				--new
				--filter-tcp=443 --filter-l7=tls --hostlist=/opt/zapret2/ipset/zapret-hosts-google.txt --payload=tls_client_hello --lua-desync=fake:blob=tls_google:repeats=6:ip_id=zero:tcp_seq=1000:tcp_ack=-66000:tcp_ts_up --lua-desync=multisplit:ip_id=zero
				--new
				--filter-tcp=80,443 --filter-l7=http,tls <HOSTLIST> --payload=tls_client_hello --lua-desync=fake:blob=stun_fake:repeats=6:tcp_seq=1000:tcp_ack=-66000:tcp_ts_up --lua-desync=fake:blob=tls_google:repeats=6:tcp_seq=1000:tcp_ack=-66000:tcp_ts_up --lua-desync=multisplit --payload=http_req --lua-desync=fake:blob=tls_max:repeats=6:tcp_seq=1000:tcp_ack=-66000:tcp_ts_up --lua-desync=multisplit
				--new
				--filter-udp=443 --filter-l7=quic <HOSTLIST_NOAUTO> --payload=quic_initial --lua-desync=fake:blob=quic_google:repeats=6
				--new
				--filter-udp=19294-19344,50000-50100 --filter-l7=discord,stun --payload=discord_ip_discovery,stun --lua-desync=fake:blob=discord_udp:repeats=6
			"
			commit $cfgname
		EOF
	fi
	if [ "$strat" = "zm_alt4_mod_maximusng" ]; then
		uci batch <<-EOF
			set $cfgname.config.MODE_FILTER='hostlist'
			set $cfgname.config.NFQWS2_PORTS_TCP='80,443,2053,2083,2087,2096,8443'
			set $cfgname.config.NFQWS2_PORTS_UDP='443,19294-19344,50000-50100'
			set $cfgname.config.NFQWS2_OPT="
				--comment=Strategy__zm_alt4_mod_maximusng
				--blob=quic_google:@/opt/zapret2/files/fake/quic_initial_www_google_com.bin
				--blob=tls_google:@/opt/zapret2/files/fake/tls_clienthello_www_google_com.bin
				--blob=tls_max:@/opt/zapret2/files/fake/tls_clienthello_max_ru.bin
				--blob=tls_sochi:@/opt/zapret2/files/fake/tls_clienthello_sochi_park.bin
				--blob=stun_fake:@/opt/zapret2/files/fake/stun.bin
				--blob=discord_udp:@/opt/zapret2/files/fake/ACTIVE_DISCORD_UDP.bin
				--blob=game_udp:@/opt/zapret2/files/fake/ACTIVE_GAME_UDP.bin
				--filter-tcp=2053,2083,2087,2096,8443 --filter-l7=tls --hostlist-domains=discord.media --payload=tls_client_hello --lua-desync=fake:blob=tls_google:repeats=6:tcp_seq=1000:tcp_ack=-66000:tcp_ts_up --lua-desync=multisplit
				--new
				--filter-tcp=80,443 --filter-l7=http,tls <HOSTLIST> --payload=tls_client_hello --lua-desync=fake:blob=stun_fake:repeats=6:tcp_seq=1000:tcp_ack=-66000:tcp_ts_up --lua-desync=fake:blob=tls_google:repeats=6:tcp_seq=1000:tcp_ack=-66000:tcp_ts_up --lua-desync=multisplit --payload=http_req --lua-desync=fake:blob=tls_sochi:repeats=5:tcp_ts=-600000:tcp_ts_up --lua-desync=hostfakesplit:host=mail.ru:tcp_ts=-600000:tc
				--new
				--filter-udp=443 --filter-l7=quic <HOSTLIST_NOAUTO> --payload=quic_initial --lua-desync=fake:blob=quic_google:repeats=6
				--new
				--filter-udp=19294-19344,50000-50100 --filter-l7=discord,stun --payload=discord_ip_discovery,stun --lua-desync=fake:blob=discord_udp:repeats=6
			"
			commit $cfgname
		EOF
	fi
	if [ "$strat" = "zm_alt5" ]; then
		uci batch <<-EOF
			set $cfgname.config.MODE_FILTER='hostlist'
			set $cfgname.config.NFQWS2_PORTS_TCP='80,443,2053,2083,2087,2096,8443'
			set $cfgname.config.NFQWS2_PORTS_UDP='443,19294-19344,50000-50100'
			set $cfgname.config.NFQWS2_OPT="
				--comment=Strategy__zm_alt5
				--blob=quic_google:@/opt/zapret2/files/fake/quic_initial_www_google_com.bin
				--blob=discord_udp:@/opt/zapret2/files/fake/ACTIVE_DISCORD_UDP.bin
				--blob=game_udp:@/opt/zapret2/files/fake/ACTIVE_GAME_UDP.bin
				--filter-l3=ipv4 --filter-tcp=2053,2083,2087,2096,8443 --filter-l7=tls,http --payload=tls_client_hello,http_req --lua-desync=syndata --lua-desync=multidisorder
				--new
				--filter-l3=ipv4 --filter-tcp=80,443 --filter-l7=http,tls <HOSTLIST> --payload=tls_client_hello --lua-desync=syndata --lua-desync=multidisorder
				--new
				--filter-udp=443 --filter-l7=quic <HOSTLIST_NOAUTO> --payload=quic_initial --lua-desync=fake:blob=quic_google:repeats=6
				--new
				--filter-udp=19294-19344,50000-50100 --filter-l7=discord,stun --payload=discord_ip_discovery,stun --lua-desync=fake:blob=discord_udp:repeats=6
			"
			commit $cfgname
		EOF
	fi
	if [ "$strat" = "zm_alt6" ]; then
		uci batch <<-EOF
			set $cfgname.config.MODE_FILTER='hostlist'
			set $cfgname.config.NFQWS2_PORTS_TCP='80,443,2053,2083,2087,2096,8443'
			set $cfgname.config.NFQWS2_PORTS_UDP='443,19294-19344,50000-50100'
			set $cfgname.config.NFQWS2_OPT="
				--comment=Strategy__zm_alt6
				--blob=quic_google:@/opt/zapret2/files/fake/quic_initial_www_google_com.bin
				--blob=tls_google:@/opt/zapret2/files/fake/tls_clienthello_www_google_com.bin
				--blob=discord_udp:@/opt/zapret2/files/fake/ACTIVE_DISCORD_UDP.bin
				--blob=game_udp:@/opt/zapret2/files/fake/ACTIVE_GAME_UDP.bin
				--filter-tcp=2053,2083,2087,2096,8443 --filter-l7=tls --hostlist-domains=discord.media --payload=tls_client_hello --lua-desync=multisplit:pos=1:seqovl=681:seqovl_pattern=tls_google
				--new
				--filter-tcp=443 --filter-l7=tls --hostlist=/opt/zapret2/ipset/zapret-hosts-google.txt --payload=tls_client_hello --lua-desync=multisplit:pos=1:seqovl=681:seqovl_pattern=tls_google:ip_id=zero
				--new
				--filter-tcp=80,443 --filter-l7=http,tls <HOSTLIST> --payload=tls_client_hello --lua-desync=multisplit:pos=1:seqovl=681:seqovl_pattern=tls_google --payload=http_req --lua-desync=multisplit:pos=1:seqovl=681:seqovl_pattern=tls_google
				--new
				--filter-udp=443 --filter-l7=quic <HOSTLIST_NOAUTO> --payload=quic_initial --lua-desync=fake:blob=quic_google:repeats=6
				--new
				--filter-udp=19294-19344,50000-50100 --filter-l7=discord,stun --payload=discord_ip_discovery,stun --lua-desync=fake:blob=discord_udp:repeats=6
			"
			commit $cfgname
		EOF
	fi
	if [ "$strat" = "zm_alt7" ]; then
		uci batch <<-EOF
			set $cfgname.config.MODE_FILTER='hostlist'
			set $cfgname.config.NFQWS2_PORTS_TCP='80,443,2053,2083,2087,2096,8443'
			set $cfgname.config.NFQWS2_PORTS_UDP='443,19294-19344,50000-50100'
			set $cfgname.config.NFQWS2_OPT="
				--comment=Strategy__zm_alt7
				--blob=quic_google:@/opt/zapret2/files/fake/quic_initial_www_google_com.bin
				--blob=tls_google:@/opt/zapret2/files/fake/tls_clienthello_www_google_com.bin
				--blob=discord_udp:@/opt/zapret2/files/fake/ACTIVE_DISCORD_UDP.bin
				--blob=game_udp:@/opt/zapret2/files/fake/ACTIVE_GAME_UDP.bin
				--filter-tcp=2053,2083,2087,2096,8443 --filter-l7=tls --hostlist-domains=discord.media --payload=tls_client_hello --lua-desync=multisplit:pos=2,sniext+1:seqovl=679:seqovl_pattern=tls_google
				--new
				--filter-tcp=443 --filter-l7=tls --hostlist=/opt/zapret2/ipset/zapret-hosts-google.txt --payload=tls_client_hello --lua-desync=multisplit:pos=2,sniext+1:seqovl=679:seqovl_pattern=tls_google:ip_id=zero
				--new
				--filter-tcp=80,443 --filter-l7=http,tls <HOSTLIST> --payload=tls_client_hello --lua-desync=multisplit:pos=2,sniext+1:seqovl=679:seqovl_pattern=tls_google --payload=http_req --lua-desync=multisplit:pos=2,sniext+1:seqovl=679:seqovl_pattern=tls_google
				--new
				--filter-udp=443 --filter-l7=quic <HOSTLIST_NOAUTO> --payload=quic_initial --lua-desync=fake:blob=quic_google:repeats=6
				--new
				--filter-udp=19294-19344,50000-50100 --filter-l7=discord,stun --payload=discord_ip_discovery,stun --lua-desync=fake:blob=discord_udp:repeats=6
			"
			commit $cfgname
		EOF
	fi
	if [ "$strat" = "zm_alt8" ]; then
		uci batch <<-EOF
			set $cfgname.config.MODE_FILTER='hostlist'
			set $cfgname.config.NFQWS2_PORTS_TCP='80,443,2053,2083,2087,2096,8443'
			set $cfgname.config.NFQWS2_PORTS_UDP='443,19294-19344,50000-50100'
			set $cfgname.config.NFQWS2_OPT="
				--comment=Strategy__zm_alt8
				--blob=quic_google:@/opt/zapret2/files/fake/quic_initial_www_google_com.bin
				--blob=tls_max:@/opt/zapret2/files/fake/tls_clienthello_max_ru.bin
				--blob=discord_udp:@/opt/zapret2/files/fake/ACTIVE_DISCORD_UDP.bin
				--blob=game_udp:@/opt/zapret2/files/fake/ACTIVE_GAME_UDP.bin
				--filter-tcp=2053,2083,2087,2096,8443 --filter-l7=tls --hostlist-domains=discord.media --payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:repeats=6:tcp_seq=2:tcp_ack=-66000:tcp_ts_up
				--new
				--filter-tcp=443 --filter-l7=tls --hostlist=/opt/zapret2/ipset/zapret-hosts-google.txt --payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:repeats=6:ip_id=zero:tcp_seq=2:tcp_ack=-66000:tcp_ts_up
				--new
				--filter-tcp=80,443 --filter-l7=http,tls <HOSTLIST> --payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:repeats=6:tcp_seq=2:tcp_ack=-66000:tcp_ts_up --payload=http_req --lua-desync=fake:blob=tls_max:repeats=6:tcp_seq=2:tcp_ack=-66000:tcp_ts_up
				--new
				--filter-udp=443 --filter-l7=quic <HOSTLIST_NOAUTO> --payload=quic_initial --lua-desync=fake:blob=quic_google:repeats=6
				--new
				--filter-udp=19294-19344,50000-50100 --filter-l7=discord,stun --payload=discord_ip_discovery,stun --lua-desync=fake:blob=discord_udp:repeats=6
			"
			commit $cfgname
		EOF
	fi
	if [ "$strat" = "zm_alt9" ]; then
		uci batch <<-EOF
			set $cfgname.config.MODE_FILTER='hostlist'
			set $cfgname.config.NFQWS2_PORTS_TCP='80,443,2053,2083,2087,2096,8443'
			set $cfgname.config.NFQWS2_PORTS_UDP='443,19294-19344,50000-50100'
			set $cfgname.config.NFQWS2_OPT="
				--comment=Strategy__zm_alt9
				--blob=quic_google:@/opt/zapret2/files/fake/quic_initial_www_google_com.bin
				--blob=discord_udp:@/opt/zapret2/files/fake/ACTIVE_DISCORD_UDP.bin
				--blob=game_udp:@/opt/zapret2/files/fake/ACTIVE_GAME_UDP.bin
				--filter-tcp=2053,2083,2087,2096,8443 --filter-l7=tls --hostlist-domains=discord.media --payload=tls_client_hello --lua-desync=hostfakesplit:host=www.google.com:repeats=4:tcp_ts=-600000:tcp_ts_up
				--new
				--filter-tcp=443 --filter-l7=tls --hostlist=/opt/zapret2/ipset/zapret-hosts-google.txt --payload=tls_client_hello --lua-desync=hostfakesplit:host=www.google.com:repeats=4:ip_id=zero:tcp_ts=-600000:tcp_ts_up
				--new
				--filter-tcp=80,443 --filter-l7=http,tls <HOSTLIST> --payload=tls_client_hello --lua-desync=hostfakesplit:host=ozon.ru:repeats=4:tcp_ts=-600000:tcp_md5:tcp_ts_up --payload=http_req --lua-desync=hostfakesplit:host=ozon.ru:repeats=4:tcp_ts=-600000:tcp_md5:tcp_ts_up
				--new
				--filter-udp=443 --filter-l7=quic <HOSTLIST_NOAUTO> --payload=quic_initial --lua-desync=fake:blob=quic_google:repeats=6
				--new
				--filter-udp=19294-19344,50000-50100 --filter-l7=discord,stun --payload=discord_ip_discovery,stun --lua-desync=fake:blob=discord_udp:repeats=6
			"
			commit $cfgname
		EOF
	fi
	if [ "$strat" = "zm_alt10" ]; then
		uci batch <<-EOF
			set $cfgname.config.MODE_FILTER='hostlist'
			set $cfgname.config.NFQWS2_PORTS_TCP='80,443,2053,2083,2087,2096,8443'
			set $cfgname.config.NFQWS2_PORTS_UDP='443,19294-19344,50000-50100'
			set $cfgname.config.NFQWS2_OPT="
				--comment=Strategy__zm_alt10
				--blob=quic_google:@/opt/zapret2/files/fake/quic_initial_www_google_com.bin
				--blob=tls_google:@/opt/zapret2/files/fake/tls_clienthello_www_google_com.bin
				--blob=tls_4pda:@/opt/zapret2/files/fake/tls_clienthello_4pda_to.bin
				--blob=tls_max:@/opt/zapret2/files/fake/tls_clienthello_max_ru.bin
				--blob=stun_fake:@/opt/zapret2/files/fake/stun.bin
				--blob=discord_udp:@/opt/zapret2/files/fake/ACTIVE_DISCORD_UDP.bin
				--blob=game_udp:@/opt/zapret2/files/fake/ACTIVE_GAME_UDP.bin
				--filter-tcp=2053,2083,2087,2096,8443 --filter-l7=tls --hostlist-domains=discord.media --payload=tls_client_hello --lua-desync=fake:blob=tls_google:repeats=6:tcp_ts=-600000:tcp_ts_up
				--new
				--filter-tcp=443 --filter-l7=tls --hostlist=/opt/zapret2/ipset/zapret-hosts-google.txt --payload=tls_client_hello --lua-desync=fake:blob=tls_google:repeats=6:ip_id=zero:tcp_ts=-600000:tcp_ts_up
				--new
				--filter-tcp=80,443 --filter-l7=http,tls <HOSTLIST> --payload=tls_client_hello --lua-desync=fake:blob=stun_fake:repeats=6:tcp_ts=-600000:tcp_ts_up --lua-desync=fake:blob=tls_4pda:repeats=6:tcp_ts=-600000:tcp_ts_up --payload=http_req --lua-desync=fake:blob=tls_max:repeats=6:tcp_ts=-600000:tcp_ts_up
				--new
				--filter-udp=443 --filter-l7=quic <HOSTLIST_NOAUTO> --payload=quic_initial --lua-desync=fake:blob=quic_google:repeats=6
				--new
				--filter-udp=19294-19344,50000-50100 --filter-l7=discord,stun --payload=discord_ip_discovery,stun --lua-desync=fake:blob=discord_udp:repeats=6
			"
			commit $cfgname
		EOF
	fi
	if [ "$strat" = "zm_alt11" ]; then
		uci batch <<-EOF
			set $cfgname.config.MODE_FILTER='hostlist'
			set $cfgname.config.NFQWS2_PORTS_TCP='80,443,2053,2083,2087,2096,8443'
			set $cfgname.config.NFQWS2_PORTS_UDP='443,19294-19344,50000-50100'
			set $cfgname.config.NFQWS2_OPT="
				--comment=Strategy__zm_alt11
				--blob=quic_google:@/opt/zapret2/files/fake/quic_initial_www_google_com.bin
				--blob=tls_google:@/opt/zapret2/files/fake/tls_clienthello_www_google_com.bin
				--blob=tls_max:@/opt/zapret2/files/fake/tls_clienthello_max_ru.bin
				--blob=stun_fake:@/opt/zapret2/files/fake/stun2.bin
				--blob=discord_udp:@/opt/zapret2/files/fake/ACTIVE_DISCORD_UDP.bin
				--blob=game_udp:@/opt/zapret2/files/fake/ACTIVE_GAME_UDP.bin
				--filter-tcp=2053,2083,2087,2096,8443 --filter-l7=tls --hostlist-domains=discord.media --payload=tls_client_hello --lua-desync=fake:blob=tls_google:repeats=8:tcp_ts=-600000:tcp_ts_up --lua-desync=multisplit:pos=1:seqovl=681:seqovl_pattern=tls_google
				--new
				--filter-tcp=443 --filter-l7=tls --hostlist=/opt/zapret2/ipset/zapret-hosts-google.txt --payload=tls_client_hello --lua-desync=fake:blob=tls_google:repeats=8:ip_id=zero:tcp_ts=-600000:tcp_ts_up --lua-desync=multisplit:pos=1:seqovl=681:seqovl_pattern=tls_google:ip_id=zero
				--new
				--filter-tcp=80,443 --filter-l7=http,tls <HOSTLIST> --payload=tls_client_hello --lua-desync=fake:blob=stun_fake:repeats=8:tcp_ts=-600000:tcp_ts_up --lua-desync=fake:blob=tls_max:repeats=8:tcp_ts=-600000:tcp_ts_up --lua-desync=multisplit:pos=1:seqovl=664:seqovl_pattern=tls_max --payload=http_req --lua-desync=fake:blob=tls_max:repeats=8:tcp_ts=-600000:tcp_ts_up --lua-desync=multisplit:pos=1:seqovl=664:seqovl_pattern=tls_max
				--new
				--filter-udp=443 --filter-l7=quic <HOSTLIST_NOAUTO> --payload=quic_initial --lua-desync=fake:blob=quic_google:repeats=11
				--new
				--filter-udp=19294-19344,50000-50100 --filter-l7=discord,stun --payload=discord_ip_discovery,stun --lua-desync=fake:blob=discord_udp:repeats=6
			"
			commit $cfgname
		EOF
	fi
	if [ "$strat" = "zm_alt12" ]; then
		uci batch <<-EOF
			set $cfgname.config.MODE_FILTER='hostlist'
			set $cfgname.config.NFQWS2_PORTS_TCP='80,443,2053,2083,2087,2096,8443'
			set $cfgname.config.NFQWS2_PORTS_UDP='443,19294-19344,50000-50100'
			set $cfgname.config.NFQWS2_OPT="
				--comment=Strategy__zm_alt12
				--blob=quic_google:@/opt/zapret2/files/fake/quic_initial_www_google_com.bin
				--blob=tls_google:@/opt/zapret2/files/fake/tls_clienthello_www_google_com.bin
				--blob=tls_max:@/opt/zapret2/files/fake/tls_clienthello_max_ru.bin
				--blob=stun_fake:@/opt/zapret2/files/fake/stun.bin
				--blob=discord_udp:@/opt/zapret2/files/fake/ACTIVE_DISCORD_UDP.bin
				--blob=game_udp:@/opt/zapret2/files/fake/ACTIVE_GAME_UDP.bin
				--filter-tcp=2053,2083,2087,2096,8443 --filter-l7=tls --hostlist-domains=discord.media --payload=tls_client_hello --lua-desync=fake:blob=tls_google:repeats=8:tcp_ts=-600000:tcp_ts_up --lua-desync=multisplit:pos=1:seqovl=681:seqovl_pattern=tls_google
				--new
				--filter-tcp=443 --filter-l7=tls --hostlist=/opt/zapret2/ipset/zapret-hosts-google.txt --payload=tls_client_hello --lua-desync=hostfakesplit:host=www.google.com:ip_id=zero:tcp_ts=-600000:tcp_ts_up
				--new
				--filter-tcp=80,443 --filter-l7=http,tls <HOSTLIST> --payload=tls_client_hello --lua-desync=fake:blob=stun_fake:repeats=8:tcp_ts=-600000:tcp_ts_up --lua-desync=fake:blob=tls_max:repeats=8:tcp_ts=-600000:tcp_ts_up --lua-desync=multisplit:pos=1:seqovl=664:seqovl_pattern=tls_max --payload=http_req --lua-desync=fake:blob=tls_max:repeats=8:tcp_ts=-600000:tcp_ts_up --lua-desync=multisplit:pos=1:seqovl=664:seqovl_pattern=tls_max
				--new
				--filter-udp=443 --filter-l7=quic <HOSTLIST_NOAUTO> --payload=quic_initial --lua-desync=fake:blob=quic_google:repeats=11
				--new
				--filter-udp=19294-19344,50000-50100 --filter-l7=discord,stun --payload=discord_ip_discovery --lua-desync=fake:blob=stun_fake:repeats=3 --lua-desync=fake:blob=discord_udp:repeats=3 --payload=stun --lua-desync=fake:blob=discord_udp:repeats=3
			"
			commit $cfgname
		EOF
	fi
	if [ "$strat" = "zm_alt13" ]; then
		uci batch <<-EOF
			set $cfgname.config.MODE_FILTER='hostlist'
			set $cfgname.config.NFQWS2_PORTS_TCP='80,443,2053,2083,2087,2096,8443'
			set $cfgname.config.NFQWS2_PORTS_UDP='443,19294-19344,50000-50100'
			set $cfgname.config.NFQWS2_OPT="
				--comment=Strategy__zm_alt13
				--blob=quic_google:@/opt/zapret2/files/fake/quic_initial_www_google_com.bin
				--blob=tls_google:@/opt/zapret2/files/fake/tls_clienthello_www_google_com.bin
				--blob=tls_sochi:@/opt/zapret2/files/fake/tls_clienthello_sochi_park.bin
				--blob=stun2_fake:@/opt/zapret2/files/fake/stun2.bin
				--blob=discord_udp:@/opt/zapret2/files/fake/ACTIVE_DISCORD_UDP.bin
				--blob=game_udp:@/opt/zapret2/files/fake/ACTIVE_GAME_UDP.bin
				--filter-tcp=2053,2083,2087,2096,8443 --filter-l7=tls --hostlist-domains=discord.media --payload=tls_client_hello --lua-desync=fake:blob=tls_google:repeats=7:tcp_ts=-600000:tcp_ts_up --lua-desync=multisplit:pos=1:seqovl=681:seqovl_pattern=tls_google
				--new
				--filter-tcp=443 --filter-l7=tls --hostlist=/opt/zapret2/ipset/zapret-hosts-google.txt --payload=tls_client_hello --lua-desync=hostfakesplit:host=www.google.com:tcp_ts=-600000:tcp_ts_up
				--new
				--filter-tcp=80,443 --filter-l7=http,tls <HOSTLIST> --payload=tls_client_hello --lua-desync=fake:blob=tls_sochi:repeats=5:tcp_ts=-600000:tcp_ts_up --lua-desync=fake:blob=stun2_fake:repeats=5:tcp_ts=-600000:tcp_ts_up --lua-desync=hostfakesplit:host=mail.ru:tcp_ts=-600000:tcp_ts_up --payload=http_req --lua-desync=fake:blob=tls_sochi:repeats=5:tcp_ts=-600000:tcp_ts_up --lua-desync=hostfakesplit:host=mail.ru:tcp_ts=-600000:tcp_ts_up
				--new
				--filter-udp=443 --filter-l7=quic <HOSTLIST_NOAUTO> --payload=quic_initial --lua-desync=fake:blob=quic_google:repeats=11
				--new
				--filter-udp=19294-19344,50000-50100 --filter-l7=discord,stun --payload=discord_ip_discovery,stun --lua-desync=fake:blob=discord_udp:repeats=5
			"
			commit $cfgname
		EOF
	fi
	if [ "$strat" = "zm_fake_tls_auto" ]; then
		uci batch <<-EOF
			set $cfgname.config.MODE_FILTER='hostlist'
			set $cfgname.config.NFQWS2_PORTS_TCP='80,443,2053,2083,2087,2096,8443'
			set $cfgname.config.NFQWS2_PORTS_UDP='443,19294-19344,50000-50100'
			set $cfgname.config.NFQWS2_OPT="
				--comment=Strategy__zm_fake_tls_auto
				--blob=quic_google:@/opt/zapret2/files/fake/quic_initial_www_google_com.bin
				--blob=tls_max:@/opt/zapret2/files/fake/tls_clienthello_max_ru.bin
				--blob=discord_udp:@/opt/zapret2/files/fake/ACTIVE_DISCORD_UDP.bin
				--blob=game_udp:@/opt/zapret2/files/fake/ACTIVE_GAME_UDP.bin
				--filter-tcp=2053,2083,2087,2096,8443 --filter-l7=tls --hostlist-domains=discord.media --payload=tls_client_hello --lua-desync=fake:blob=0x00000000:repeats=11:tcp_seq=-10000:tcp_ack=-66000:tcp_ts_up --lua-desync=fake:blob=fake_default_tls:tls_mod=rnd,dupsid,sni=www.google.com:repeats=11:tcp_seq=-10000:tcp_ack=-66000:tcp_ts_up --lua-desync=multidisorder:pos=1,midsld
				--new
				--filter-tcp=443 --filter-l7=tls --hostlist=/opt/zapret2/ipset/zapret-hosts-google.txt --payload=tls_client_hello --lua-desync=fake:blob=0x00000000:repeats=11:tcp_seq=-10000:tcp_ack=-66000:tcp_ts_up:ip_id=zero --lua-desync=fake:blob=fake_default_tls:tls_mod=rnd,dupsid,sni=www.google.com:repeats=11:tcp_seq=-10000:tcp_ack=-66000:tcp_ts_up:ip_id=zero --lua-desync=multidisorder:pos=1,midsld:ip_id=zero
				--new
				--filter-tcp=80,443 --filter-l7=http,tls <HOSTLIST> --payload=tls_client_hello --lua-desync=fake:blob=0x00000000:repeats=11:tcp_seq=-10000:tcp_ack=-66000:tcp_ts_up --lua-desync=fake:blob=fake_default_tls:tls_mod=rnd,dupsid,sni=www.google.com:repeats=11:tcp_seq=-10000:tcp_ack=-66000:tcp_ts_up --lua-desync=multidisorder:pos=1,midsld --payload=http_req --lua-desync=fake:blob=tls_max:repeats=11:tcp_seq=-10000:tcp_ack=-66000:tcp_ts_up --lua-desync=multidisorder:pos=1,midsld
				--new
				--filter-udp=443 --filter-l7=quic <HOSTLIST_NOAUTO> --payload=quic_initial --lua-desync=fake:blob=quic_google:repeats=11
				--new
				--filter-udp=19294-19344,50000-50100 --filter-l7=discord,stun --payload=discord_ip_discovery,stun --lua-desync=fake:blob=discord_udp:repeats=6
			"
			commit $cfgname
		EOF
	fi
	if [ "$strat" = "zm_fake_tls_auto_alt" ]; then
		uci batch <<-EOF
			set $cfgname.config.MODE_FILTER='hostlist'
			set $cfgname.config.NFQWS2_PORTS_TCP='80,443,2053,2083,2087,2096,8443'
			set $cfgname.config.NFQWS2_PORTS_UDP='443,19294-19344,50000-50100'
			set $cfgname.config.NFQWS2_OPT="
				--comment=Strategy__zm_fake_tls_auto_alt
				--blob=quic_google:@/opt/zapret2/files/fake/quic_initial_www_google_com.bin
				--blob=tls_max:@/opt/zapret2/files/fake/tls_clienthello_max_ru.bin
				--blob=discord_udp:@/opt/zapret2/files/fake/ACTIVE_DISCORD_UDP.bin
				--blob=game_udp:@/opt/zapret2/files/fake/ACTIVE_GAME_UDP.bin
				--filter-tcp=2053,2083,2087,2096,8443 --filter-l7=tls --hostlist-domains=discord.media --payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:tls_mod=rnd,dupsid,sni=www.google.com:repeats=8:tcp_seq=2:tcp_ack=-66000:tcp_ts_up --lua-desync=fakedsplit:pos=1:repeats=8:tcp_seq=2:tcp_ack=-66000:tcp_ts_up
				--new
				--filter-tcp=443 --filter-l7=tls --hostlist=/opt/zapret2/ipset/zapret-hosts-google.txt --payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:tls_mod=rnd,dupsid,sni=www.google.com:repeats=8:tcp_seq=2:tcp_ack=-66000:tcp_ts_up:ip_id=zero --lua-desync=fakedsplit:pos=1:repeats=8:tcp_seq=2:tcp_ack=-66000:tcp_ts_up:ip_id=zero
				--new
				--filter-tcp=80,443 --filter-l7=http,tls <HOSTLIST> --payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:tls_mod=rnd,dupsid,sni=www.google.com:repeats=8:tcp_seq=2:tcp_ack=-66000:tcp_ts_up --lua-desync=fakedsplit:pos=1:repeats=8:tcp_seq=2:tcp_ack=-66000:tcp_ts_up --payload=http_req --lua-desync=fake:blob=tls_max:repeats=8:tcp_seq=2:tcp_ack=-66000:tcp_ts_up --lua-desync=fakedsplit:pos=1:repeats=8:tcp_seq=2:tcp_ack=-66000:tcp_ts_up
				--new
				--filter-udp=443 --filter-l7=quic <HOSTLIST_NOAUTO> --payload=quic_initial --lua-desync=fake:blob=quic_google:repeats=11
				--new
				--filter-udp=19294-19344,50000-50100 --filter-l7=discord,stun --payload=discord_ip_discovery,stun --lua-desync=fake:blob=discord_udp:repeats=6
			"
			commit $cfgname
		EOF
	fi
	if [ "$strat" = "zm_fake_tls_auto_alt2" ]; then
		uci batch <<-EOF
			set $cfgname.config.MODE_FILTER='hostlist'
			set $cfgname.config.NFQWS2_PORTS_TCP='80,443,2053,2083,2087,2096,8443'
			set $cfgname.config.NFQWS2_PORTS_UDP='443,19294-19344,50000-50100'
			set $cfgname.config.NFQWS2_OPT="
				--comment=Strategy__zm_fake_tls_auto_alt2
				--blob=quic_google:@/opt/zapret2/files/fake/quic_initial_www_google_com.bin
				--blob=tls_google:@/opt/zapret2/files/fake/tls_clienthello_www_google_com.bin
				--blob=tls_max:@/opt/zapret2/files/fake/tls_clienthello_max_ru.bin
				--blob=discord_udp:@/opt/zapret2/files/fake/ACTIVE_DISCORD_UDP.bin
				--blob=game_udp:@/opt/zapret2/files/fake/ACTIVE_GAME_UDP.bin
				--filter-tcp=2053,2083,2087,2096,8443 --filter-l7=tls --hostlist-domains=discord.media --payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:tls_mod=rnd,dupsid,sni=www.google.com:repeats=8:tcp_seq=10000000:tcp_ack=-66000:tcp_ts_up --lua-desync=multisplit:pos=1:seqovl=681:seqovl_pattern=tls_google
				--new
				--filter-tcp=443 --filter-l7=tls --hostlist=/opt/zapret2/ipset/zapret-hosts-google.txt --payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:tls_mod=rnd,dupsid,sni=www.google.com:repeats=8:tcp_seq=10000000:tcp_ack=-66000:tcp_ts_up:ip_id=zero --lua-desync=multisplit:pos=1:seqovl=681:seqovl_pattern=tls_google:ip_id=zero
				--new
				--filter-tcp=80,443 --filter-l7=http,tls <HOSTLIST> --payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:tls_mod=rnd,dupsid,sni=www.google.com:repeats=8:tcp_seq=10000000:tcp_ack=-66000:tcp_ts_up --lua-desync=multisplit:pos=1:seqovl=681:seqovl_pattern=tls_google --payload=http_req --lua-desync=fake:blob=tls_max:repeats=8:tcp_seq=10000000:tcp_ack=-66000:tcp_ts_up --lua-desync=multisplit:pos=1:seqovl=681:seqovl_pattern=tls_google
				--new
				--filter-udp=443 --filter-l7=quic <HOSTLIST_NOAUTO> --payload=quic_initial --lua-desync=fake:blob=quic_google:repeats=11
				--new
				--filter-udp=19294-19344,50000-50100 --filter-l7=discord,stun --payload=discord_ip_discovery,stun --lua-desync=fake:blob=discord_udp:repeats=6
			"
			commit $cfgname
		EOF
	fi
	if [ "$strat" = "zm_fake_tls_auto_alt3" ]; then
		uci batch <<-EOF
			set $cfgname.config.MODE_FILTER='hostlist'
			set $cfgname.config.NFQWS2_PORTS_TCP='80,443,2053,2083,2087,2096,8443'
			set $cfgname.config.NFQWS2_PORTS_UDP='443,19294-19344,50000-50100'
			set $cfgname.config.NFQWS2_OPT="
				--comment=Strategy__zm_fake_tls_auto_alt3
				--blob=quic_google:@/opt/zapret2/files/fake/quic_initial_www_google_com.bin
				--blob=tls_google:@/opt/zapret2/files/fake/tls_clienthello_www_google_com.bin
				--blob=tls_max:@/opt/zapret2/files/fake/tls_clienthello_max_ru.bin
				--blob=discord_udp:@/opt/zapret2/files/fake/ACTIVE_DISCORD_UDP.bin
				--blob=game_udp:@/opt/zapret2/files/fake/ACTIVE_GAME_UDP.bin
				--filter-tcp=2053,2083,2087,2096,8443 --filter-l7=tls --hostlist-domains=discord.media --payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:tls_mod=rnd,dupsid,sni=www.google.com:repeats=8:tcp_ts=-600000:tcp_ts_up --lua-desync=multisplit:pos=1:seqovl=681:seqovl_pattern=tls_google
				--new
				--filter-tcp=443 --filter-l7=tls --hostlist=/opt/zapret2/ipset/zapret-hosts-google.txt --payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:tls_mod=rnd,dupsid,sni=www.google.com:repeats=8:tcp_ts=-600000:tcp_ts_up:ip_id=zero --lua-desync=multisplit:pos=1:seqovl=681:seqovl_pattern=tls_google:ip_id=zero
				--new
				--filter-tcp=80,443 --filter-l7=http,tls <HOSTLIST> --payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:tls_mod=rnd,dupsid,sni=www.google.com:repeats=8:tcp_ts=-600000:tcp_ts_up --lua-desync=multisplit:pos=1:seqovl=681:seqovl_pattern=tls_google --payload=http_req --lua-desync=fake:blob=tls_max:repeats=8:tcp_ts=-600000:tcp_ts_up --lua-desync=multisplit:pos=1:seqovl=681:seqovl_pattern=tls_google
				--new
				--filter-udp=443 --filter-l7=quic <HOSTLIST_NOAUTO> --payload=quic_initial --lua-desync=fake:blob=quic_google:repeats=11
				--new
				--filter-udp=19294-19344,50000-50100 --filter-l7=discord,stun --payload=discord_ip_discovery,stun --lua-desync=fake:blob=discord_udp:repeats=6
			"
			commit $cfgname
		EOF
	fi
	if [ "$strat" = "zm_simple_fake" ]; then
		uci batch <<-EOF
			set $cfgname.config.MODE_FILTER='hostlist'
			set $cfgname.config.NFQWS2_PORTS_TCP='80,443,2053,2083,2087,2096,8443'
			set $cfgname.config.NFQWS2_PORTS_UDP='443,19294-19344,50000-50100'
			set $cfgname.config.NFQWS2_OPT="
				--comment=Strategy__zm_simple_fake
				--blob=quic_google:@/opt/zapret2/files/fake/quic_initial_www_google_com.bin
				--blob=tls_google:@/opt/zapret2/files/fake/tls_clienthello_www_google_com.bin
				--blob=tls_max:@/opt/zapret2/files/fake/tls_clienthello_max_ru.bin
				--blob=stun_fake:@/opt/zapret2/files/fake/stun2.bin
				--blob=discord_udp:@/opt/zapret2/files/fake/ACTIVE_DISCORD_UDP.bin
				--blob=game_udp:@/opt/zapret2/files/fake/ACTIVE_GAME_UDP.bin
				--filter-tcp=2053,2083,2087,2096,8443 --filter-l7=tls --hostlist-domains=discord.media --payload=tls_client_hello --lua-desync=fake:blob=tls_google:repeats=6:tcp_ts=-600000:tcp_ts_up
				--new
				--filter-tcp=443 --filter-l7=tls --hostlist=/opt/zapret2/ipset/zapret-hosts-google.txt --payload=tls_client_hello --lua-desync=hostfakesplit:host=www.google.com:ip_id=zero:tcp_ts=-600000:tcp_ts_up
				--new
				--filter-tcp=80,443 --filter-l7=http,tls <HOSTLIST> --payload=tls_client_hello --lua-desync=fake:blob=tls_google:repeats=6:tcp_ts=-600000:tcp_ts_up --payload=http_req --lua-desync=fake:blob=tls_max:repeats=6:tcp_ts=-600000:tcp_ts_up
				--new
				--filter-udp=443 --filter-l7=quic <HOSTLIST_NOAUTO> --payload=quic_initial --lua-desync=fake:blob=quic_google:repeats=6
				--new
				--filter-udp=19294-19344,50000-50100 --filter-l7=discord,stun --payload=discord_ip_discovery,stun --lua-desync=fake:blob=discord_udp:repeats=6
			"
			commit $cfgname
		EOF
	fi
	if [ "$strat" = "zm_simple_fake_alt" ]; then
		uci batch <<-EOF
			set $cfgname.config.MODE_FILTER='hostlist'
			set $cfgname.config.NFQWS2_PORTS_TCP='80,443,2053,2083,2087,2096,8443'
			set $cfgname.config.NFQWS2_PORTS_UDP='443,19294-19344,50000-50100'
			set $cfgname.config.NFQWS2_OPT="
				--comment=Strategy__zm_simple_fake_alt
				--blob=quic_google:@/opt/zapret2/files/fake/quic_initial_www_google_com.bin
				--blob=tls_google:@/opt/zapret2/files/fake/tls_clienthello_www_google_com.bin
				--blob=tls_max:@/opt/zapret2/files/fake/tls_clienthello_max_ru.bin
				--blob=stun_fake:@/opt/zapret2/files/fake/stun2.bin
				--blob=discord_udp:@/opt/zapret2/files/fake/ACTIVE_DISCORD_UDP.bin
				--blob=game_udp:@/opt/zapret2/files/fake/ACTIVE_GAME_UDP.bin
				--filter-tcp=2053,2083,2087,2096,8443 --filter-l7=tls --hostlist-domains=discord.media --payload=tls_client_hello --lua-desync=fake:blob=tls_google:repeats=6:tcp_seq=2:tcp_ack=-66000:tcp_ts_up
				--new
				--filter-tcp=443 --filter-l7=tls --hostlist=/opt/zapret2/ipset/zapret-hosts-google.txt --payload=tls_client_hello --lua-desync=fake:blob=tls_google:repeats=6:ip_id=zero:tcp_seq=2:tcp_ack=-66000:tcp_ts_up
				--new
				--filter-tcp=80,443 --filter-l7=http,tls <HOSTLIST> --payload=tls_client_hello --lua-desync=fake:blob=stun_fake:repeats=6:tcp_seq=2:tcp_ack=-66000:tcp_ts_up --lua-desync=fake:blob=tls_google:repeats=6:tcp_seq=2:tcp_ack=-66000:tcp_ts_up --payload=http_req --lua-desync=fake:blob=tls_max:repeats=6:tcp_seq=2:tcp_ack=-66000:tcp_ts_up
				--new
				--filter-udp=443 --filter-l7=quic <HOSTLIST_NOAUTO> --payload=quic_initial --lua-desync=fake:blob=quic_google:repeats=6
				--new
				--filter-udp=19294-19344,50000-50100 --filter-l7=discord,stun --payload=discord_ip_discovery,stun --lua-desync=fake:blob=discord_udp:repeats=6
			"
			commit $cfgname
		EOF
	fi
	if [ "$strat" = "zm_simple_fake_alt2" ]; then
		uci batch <<-EOF
			set $cfgname.config.MODE_FILTER='hostlist'
			set $cfgname.config.NFQWS2_PORTS_TCP='80,443,2053,2083,2087,2096,8443'
			set $cfgname.config.NFQWS2_PORTS_UDP='443,19294-19344,50000-50100'
			set $cfgname.config.NFQWS2_OPT="
				--comment=Strategy__zm_simple_fake_alt2
				--blob=quic_google:@/opt/zapret2/files/fake/quic_initial_www_google_com.bin
				--blob=tls_google:@/opt/zapret2/files/fake/tls_clienthello_www_google_com.bin
				--blob=tls_max:@/opt/zapret2/files/fake/tls_clienthello_max_ru.bin
				--blob=stun_fake:@/opt/zapret2/files/fake/stun2.bin
				--blob=discord_udp:@/opt/zapret2/files/fake/ACTIVE_DISCORD_UDP.bin
				--blob=game_udp:@/opt/zapret2/files/fake/ACTIVE_GAME_UDP.bin
				--filter-tcp=2053,2083,2087,2096,8443 --filter-l7=tls --hostlist-domains=discord.media --payload=tls_client_hello --lua-desync=fake:blob=tls_google:repeats=6:tcp_ts=-600000:tcp_ts_up
				--new
				--filter-tcp=443 --filter-l7=tls --hostlist=/opt/zapret2/ipset/zapret-hosts-google.txt --payload=tls_client_hello --lua-desync=fake:blob=tls_google:repeats=6:ip_id=zero:tcp_ts=-600000:tcp_ts_up
				--new
				--filter-tcp=80,443 --filter-l7=http,tls <HOSTLIST> --payload=tls_client_hello --lua-desync=fake:blob=stun_fake:repeats=6:tcp_ts=-600000:tcp_ts_up --lua-desync=fake:blob=tls_max:repeats=6:tcp_ts=-600000:tcp_ts_up --payload=http_req --lua-desync=fake:blob=tls_max:repeats=6:tcp_ts=-600000:tcp_ts_up
				--new
				--filter-udp=443 --filter-l7=quic <HOSTLIST_NOAUTO> --payload=quic_initial --lua-desync=fake:blob=quic_google:repeats=6
				--new
				--filter-udp=19294-19344,50000-50100 --filter-l7=discord,stun --payload=discord_ip_discovery,stun --lua-desync=fake:blob=discord_udp:repeats=6
			"
			commit $cfgname
		EOF
	fi
	if [ "$strat" = "zm_hardcorp74" ]; then
		uci batch <<-EOF
			set $cfgname.config.MODE_FILTER='hostlist'
			set $cfgname.config.NFQWS2_PORTS_TCP='80,443,1984,2053,2083,2087,2096,5222,8443'
			set $cfgname.config.NFQWS2_PORTS_UDP='443,590-600,1400,3478-3481,5349,19294-19344,35349,49152-65535'
			set $cfgname.config.NFQWS2_OPT="
				--comment=Strategy__zm_hardcorp74
				--blob=quic_initial:@/opt/zapret2/files/fake/quic_initial.bin
				--blob=quic_initial_vk_com:@/opt/zapret2/files/fake/quic_initial_vk_com.bin
				--blob=tls_clienthello:@/opt/zapret2/files/fake/tls_clienthello.bin
				--blob=stun_fake:@/opt/zapret2/files/fake/stun.bin
				--blob=tls_sochi:@/opt/zapret2/files/fake/tls_clienthello_sochi_park.bin
				--blob=discord_udp:@/opt/zapret2/files/fake/quic_initial_steamcommunity_com.bin
				--blob=zero:0x00000000
				--filter-tcp=443 --filter-l7=tls --hostlist=/opt/zapret2/ipset/zapret-hosts-google.txt --payload=tls_client_hello --lua-desync=multidisorder:pos=1,sniext+1,host+1,midsld-2,midsld,midsld+2,endhost-1 --lua-desync=fake:blob=tls_clienthello:optional:tcp_seq=-10000:tcp_ack=-66000:badsum:tls_mod=rnd,dupsid,sni=rzd.ru:repeats=4
				--new
				--filter-tcp=443 <HOSTLIST> --payload=tls_client_hello --lua-desync=hostfakesplit:host=www.google.com:midhost=host-4:altorder=0:badsum:md5sig:badseq:badseq_increment=0:ip_id=seqgroup:tcp_ts_up
				--new
				--filter-udp=49152-65535 --ipset=/opt/zapret2/ipset/cust1.txt --payload=unknown --lua-desync=fake:blob=quic_initial:payload=unknown:repeats=12
				--new
				--filter-tcp=443,80,1984,5222 --filter-l7=http,tls,mtproto <HOSTLIST> --payload=tls_client_hello,mtproto_initial --lua-desync=circular:fails=2:time=300:retrans=3:nld=2 --lua-desync=multisplit:pos=1,midsld:seqovl=568:seqovl_pattern=stun_fake:strategy=1 --lua-desync=multisplit:pos=1,sniext+1:seqovl=582:seqovl_pattern=stun_fake:repeats=2-4:badsum:badseq:md5sig:strategy=1 --lua-desync=fake:blob=tls_clienthello:tls_mod=rnd,dupsid,sni=www.google.com:tcp_ts=-1500:badsum:badseq:md5sig:tcp_md5:repeats=5:strategy=1 --lua-desync=hostfakesplit:host=www.google.com:midhost=midsld-2:repeats=4:ip_ttl=2:strategy=1 --lua-desync=fake:blob=tls_clienthello:tls_mod=rnd,dupsid,sni=ya.ru:tcp_seq=10000:strategy=2 --lua-desync=multisplit:pos=1,midsld:seqovl=1:seqovl_pattern=tls_clienthello:tcp_ts_up:strategy=2 --lua-desync=multidisorder:pos=1,sniext+1,host+1,midsld-2,midsld,midsld+2,endhost-1:strategy=3 --lua-desync=fake:blob=tls_clienthello:optional:tcp_seq=-10000:tcp_ack=-66000:badsum:tls_mod=rnd,dupsid,sni=rzd.ru:repeats=4:strategy=3 --payload=http_req --lua-desync=fake:blob=tls_sochi:repeats=5:tcp_ts=-600000:tcp_ts_up --lua-desync=hostfakesplit:host=mail.ru:tcp_ts=-600000:tcp_ts_up
				--new
				--filter-udp=443 --filter-l7=quic <HOSTLIST_NOAUTO> --payload=quic_initial --lua-desync=fake:blob=quic_initial:repeats=11
				--new
				--filter-udp=590-600,1400,3478-3481,5349,19294-19344,35349,49152-65535 --filter-l7=wireguard,stun,discord,mtproto,unknown --out-range=<n2 --payload=wireguard_initiation,wireguard_response,wireguard_cookie,stun,discord_ip_discovery,mtproto_initial,unknown --lua-desync=circular:fails=2:time=300:retrans=3:nld=2 --lua-desync=fake:repeats=6:strategy=1 --lua-desync=fake:blob=discord_udp:repeats=4:strategy=1 --lua-desync=fake:blob=quic_initial:repeats=6:strategy=2 --lua-desync=fake:blob=discord_udp:repeats=5:strategy=2 --lua-desync=fake:blob=quic_initial_vk_com:ip_autottl=-2,3-20:ip6_autottl=-2,3-20:payload=all:repeats=6:strategy=3
			"
			commit $cfgname
		EOF
	fi
	if [ "$strat" = "zm_eduncey" ]; then
		uci batch <<-EOF
			set $cfgname.config.MODE_FILTER='hostlist'
			set $cfgname.config.NFQWS2_PORTS_TCP='80,443,1984,2053,2083,2087,2096,5222,8443'
			set $cfgname.config.NFQWS2_PORTS_UDP='443,590-600,1400,3478-3481,5349,19294-19344,50000-50100,49152-65535'
			set $cfgname.config.NFQWS2_OPT="
				--comment=Strategy__zm_eduncey
				--blob=quic_initial:@/opt/zapret2/files/fake/quic_initial.bin
				--blob=tls_clienthello:@/opt/zapret2/files/fake/tls_clienthello.bin
				--blob=quic_dbankcloud:@/opt/zapret2/files/fake/quic_initial_dbankcloud_ru.bin
				--filter-udp=3478-3481,19294-19344,50000-50100 --filter-l7=discord,stun --lua-desync=fake:blob=quic_dbankcloud:repeats=6
				--new
				--filter-udp=3478-3481,19294-19344,50000-50100 --filter-l7=unknown --lua-desync=fake:blob=quic_dbankcloud:repeats=12:cutoff=n3
				--new
				--filter-tcp=443,80,1984,2053,2083,2087,2096,5222,8443 --filter-l7=http,tls,mtproto <HOSTLIST> --payload=tls_client_hello,mtproto_initial --lua-desync=circular:fails=2:time=300:retrans=3:nld=2 --lua-desync=fake:blob=tls_clienthello:tls_mod=rnd,dupsid,sni=fonts.google.com:tcp_seq=10000:strategy=1 --lua-desync=multisplit:pos=1,midsld:seqovl=1:seqovl_pattern=tls_clienthello:tcp_ts_up:strategy=1 --lua-desync=fake:blob=0x00000000:tcp_ack=-66000:tls_mod=rnd,dupsid,sni=www.google.com:repeats=2:strategy=2 --lua-desync=multisplit:pos=1,midsld:strategy=2 --lua-desync=hostfakesplit:host=ozon.ru:midhost=host-2:seqovl=sniext+3:seqovl_pattern=tls_clienthello:badsum:tcp_md5:tcp_ts_up:strategy=3 --lua-desync=hostfakesplit:tcp_md5:tcp_ts_up:strategy=3 --lua-desync=fake:blob=tls_clienthello:tls_mod=rnd,dupsid,sni=www.google.com:strategy=4 --lua-desync=hostfakesplit:host=www.google.com:altorder=1:fool=ts:strategy=4 --payload=http_req --lua-desync=http_methodeol:badsum
				--new
				--filter-udp=443 --filter-l7=quic <HOSTLIST_NOAUTO> --payload=quic_initial --lua-desync=fake:blob=quic_initial:repeats=11
				--new
				--filter-udp=590-600,1400,5349,49152-49999,50101-65535 --filter-l7=wireguard,mtproto,unknown --out-range=<n2 --payload=wireguard_initiation,wireguard_response,wireguard_cookie,mtproto_initial,unknown --lua-desync=circular:fails=2:time=300:retrans=3:nld=2 --lua-desync=fake:repeats=6:strategy=1 --lua-desync=fake:blob=quic_initial:repeats=6:strategy=2
			"
			commit $cfgname
		EOF
	fi
	if [ "$strat" = "zm_martinbacker" ]; then
		uci batch <<-EOF
			set $cfgname.config.MODE_FILTER='hostlist'
			set $cfgname.config.NFQWS2_PORTS_TCP='80,443,1984,2053,2083,2087,2096,5222,8443'
			set $cfgname.config.NFQWS2_PORTS_UDP='443,590-600,1400,3478-3481,5349,19294-19344,49152-65535'
			set $cfgname.config.NFQWS2_OPT="
				--comment=Strategy__zm_martinbacker
				--blob=quic_initial:@/opt/zapret2/files/fake/quic_initial.bin
				--blob=quick_dbank:@/opt/zapret2/files/fake/quic_initial_dbankcloud_ru.bin
				--blob=quick_yt:@/opt/zapret2/files/fake/quic_my_youtube_initial.bin
				--blob=tls_clienthello:@/opt/zapret2/files/fake/tls_clienthello.bin
				--blob=tls_google:@/opt/zapret2/files/fake/tls_clienthello_www_google_com.bin
				--blob=tls_max:@/opt/zapret2/files/fake/tls_clienthello_max_ru.bin
				--blob=stun:@/opt/zapret2/files/fake/stun.bin
				--hostlist-domains=googlevideo.com --filter-tcp=443 --filter-l7=tls --payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:tls_mod=rnd,dupsid,sni=www.google.com:ip_id=zero:tcp_ts=-600000:tcp_ts_up --lua-desync=hostfakesplit:host=www.google.com:ip_id=zero:tcp_ts=-600000:tcp_ts_up
				--new
				--hostlist-domains=googlevideo.com --filter-udp=443 --filter-l7=quic --payload=quic_initial --lua-desync=fake:blob=quic_initial:repeats=11
				--new
				--hostlist-domains=mobatek.net --filter-tcp=443 --filter-l7=tls --payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:tcp_md5:tls_mod=rnd,dupsid,padencap:repeats=1 --lua-desync=multisplit:pos=2 --payload=empty --out-range=<s1 --lua-desync=send:tcp_md5
				--new
				--ipset=/opt/zapret2/ipset/cust2.txt --filter-tcp=443 --filter-l7=tls --payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:tls_mod=rnd,dupsid,sni=ad.adriver.ru:tcp_ts=-1000 --lua-desync=multidisorder:pos=1,midsld,sniext+1,endhost-2,-10:seqovl=1:seqovl_pattern=tls_max:tcp_ts_up
				--new
				--ipset=/opt/zapret2/ipset/cust2.txt --filter-tcp=443 --filter-l7=tls --payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:tls_mod=rnd,dupsid,sni=hcaptcha.com:tcp_ts=-1000 --lua-desync=multidisorder:pos=1,midsld,sniext+1,endhost-2,-10:seqovl=1:seqovl_pattern=tls_max:tcp_ts_up
				--new
				--ipset=/opt/zapret2/ipset/zapret-ip-user.txt --ipset-exclude=/opt/zapret2/ipset/zapret-ip-exclude.txt --ipset-ip=0.0.0.0 --filter-tcp=443 --filter-l7=tls --payload=tls_client_hello --lua-desync=multisplit:pos=1,midsld:seqovl=568:seqovl_pattern=stun:tcp_ts_up --lua-desync=multisplit:pos=1,sniext+1:seqovl=582:seqovl_pattern=stun:repeats=2-4:badsum:badseq:md5sig:tcp_ts_up --lua-desync=fake:blob=tls_clienthello:tls_mod=rnd,dupsid,sni=www.google.com:tcp_ts=-1500:badsum:badseq:md5sig:tcp_md5:repeats=5:tcp_ts_up --lua-desync=hostfakesplit:host=www.google.com:midhost=midsld-2:repeats=4:ip_ttl=2:ip6_ttl=2:tcp_ts_up
				--new
				--ipset=/opt/zapret2/ipset/zapret-ip-user.txt --ipset-exclude=/opt/zapret2/ipset/zapret-ip-exclude.txt --ipset-ip=0.0.0.0 --filter-udp=443 --filter-l7=quic --payload=quic_initial --lua-desync=fake:blob=quic_initial:repeats=6
				--new
				--ipset=/opt/zapret2/ipset/cust2.txt --filter-tcp=443 --filter-l7=tls --payload=tls_client_hello --lua-desync=hostfakesplit:host=ya.ru:tcp_md5:badsum
				--new
				--filter-tcp=443,80,1984,5222 --filter-l7=http,tls,mtproto <HOSTLIST> --payload=tls_client_hello,mtproto_initial --out-range=-s34228 --in-range=-s5556 --lua-desync=circular:fails=2:time=300:retrans=3:nld=2 --in-range=x --lua-desync=fake:blob=tls_clienthello:tls_mod=rnd,dupsid,sni=fonts.google.com:tcp_seq=10000:strategy=1 --lua-desync=multisplit:pos=1,midsld:seqovl=1:seqovl_pattern=tls_clienthello:tcp_ts_up:strategy=1 --lua-desync=fake:blob=0x00000000:tcp_ack=-66000:tls_mod=rnd,dupsid,sni=www.google.com:repeats=2:strategy=2 --lua-desync=multisplit:pos=1,midsld:strategy=2 --lua-desync=hostfakesplit:host=ozon.ru:midhost=host-2:seqovl=sniext+3:seqovl_pattern=tls_clienthello:badsum:tcp_md5:tcp_ts_up:strategy=3 --lua-desync=hostfakesplit:tcp_md5:tcp_ts_up:strategy=3 --lua-desync=fake:blob=fake_default_tls:tls_mod=rnd,dupsid,sni=www.google.com:tcp_ts=-1000:strategy=4 --lua-desync=multidisorder:pos=1,midsld,sniext+1,endhost-2,-10:seqovl=1:seqovl_pattern=tls_clienthello:tcp_ts_up:strategy=4 --lua-desync=per_instance_condition:strategy=5 --lua-desync=fake:blob=tls_clienthello:tcp_ts=-1000:cond=cond_tcp_has_ts:strategy=5 --lua-desync=fake:blob=tls_clienthello:ip_ttl=7:ip6_ttl=4:cond=cond_tcp_has_ts:cond_neg:strategy=5 --lua-desync=multidisorder:pos=1,midsld,sniext+1,endhost-2,-10:seqovl=1:seqovl_pattern=tls_clienthello:tcp_ts_up:strategy=5 --lua-desync=per_instance_condition:strategy=6 --lua-desync=fake:blob=tls_clienthello:tls_mod=rnd,dupsid,sni=fonts.google.com:tcp_ts=-1000:cond=cond_tcp_has_ts:strategy=6 --lua-desync=fake:blob=tls_clienthello:ip_ttl=7:ip6_ttl=4:cond=cond_tcp_has_ts:cond_neg:strategy=6 --lua-desync=multisplit:pos=1:seqovl=336:seqovl_pattern=tls_clienthello:tcp_ts_up:strategy=6 --lua-desync=multisplit:pos=1:seqovl=582:seqovl_pattern=stun:strategy=7 --payload=http_req --lua-desync=http_methodeol:badsum
				--new
				--filter-udp=443 --filter-l7=quic <HOSTLIST_NOAUTO> --payload=quic_initial --lua-desync=fake:blob=quic_initial:repeats=11
				--new
				--filter-udp=590-600,1400,3478-3481,5349,19294-19344,49152-65535 --filter-l7=wireguard,stun,discord,mtproto,unknown --out-range=<n2 --payload=wireguard_initiation,wireguard_response,wireguard_cookie,stun,discord_ip_discovery,mtproto_initial,unknown --out-range=-s34228 --in-range=-s5556 --lua-desync=circular:fails=2:time=300:retrans=3:nld=2 --in-range=x --lua-desync=fake:blob=quic_initial:repeats=6:strategy=1 --lua-desync=fake:repeats=6:strategy=2
			"
			commit $cfgname
		EOF
	fi
	if [ "$strat" = "zm_uvvi2" ]; then
		uci batch <<-EOF
			set $cfgname.config.MODE_FILTER='hostlist'
			set $cfgname.config.NFQWS2_PORTS_TCP='80,443,1984,2053,2083,2087,2096,5222,8443'
			set $cfgname.config.NFQWS2_PORTS_UDP='443,3478-3481,5349,19294-19344,49152-65535'
			set $cfgname.config.NFQWS2_OPT="
				--comment=Strategy__zm_uvvi2
				--blob=quic_initial:@/opt/zapret2/files/fake/quic_initial.bin
				--blob=tls_clienthello:@/opt/zapret2/files/fake/tls_clienthello.bin
				--blob=discord_udp:@/opt/zapret2/files/fake/ACTIVE_DISCORD_UDP.bin
				--blob=discord_disc:@/opt/zapret2/files/fake/discord-ip-discovery-without-port.bin
				--filter-tcp=443,80,1984,5222 --filter-l7=http,tls,mtproto <HOSTLIST> --payload=tls_client_hello,mtproto_initial --lua-desync=circular:fails=2:time=300:retrans=3:nld=2 --lua-desync=fake:blob=tls_clienthello:tls_mod=rnd,dupsid,sni=fonts.google.com:tcp_seq=10000:strategy=1 --lua-desync=multisplit:pos=1,midsld:seqovl=1:seqovl_pattern=tls_clienthello:tcp_ts_up:strategy=1 --lua-desync=fake:blob=0x00000000:tcp_ack=-66000:tls_mod=rnd,dupsid,sni=www.google.com:repeats=2:strategy=2 --lua-desync=multisplit:pos=1,midsld:strategy=2 --lua-desync=hostfakesplit:host=ozon.ru:midhost=host-2:seqovl=sniext+3:seqovl_pattern=tls_clienthello:badsum:tcp_md5:tcp_ts_up:strategy=3 --lua-desync=hostfakesplit:tcp_md5:tcp_ts_up:strategy=3 --payload=http_req --lua-desync=http_methodeol:badsum
				--new
				--filter-udp=443 --filter-l7=quic <HOSTLIST_NOAUTO> --payload=quic_initial --lua-desync=fake:blob=quic_initial:repeats=11
				--new
				--filter-udp=3478-3481,5349,19294-19344,49152-65535 --filter-l7=discord,stun --payload=discord_ip_discovery,stun --lua-desync=circular:fails=2:time=200:retrans=2:nld=2 --lua-desync=fake:blob=discord_udp:ip_autottl=-1,3-20:repeats=12:strategy=1 --lua-desync=fake:blob=discord_udp:repeats=12:strategy=2
			"
			commit $cfgname
		EOF
	fi
	if [ "$strat" = "zm_exp" ]; then
		uci batch <<-EOF
			set $cfgname.config.MODE_FILTER='hostlist'
			set $cfgname.config.NFQWS2_PORTS_TCP='80,443,2053,2083,2087,2096,8443'
			set $cfgname.config.NFQWS2_PORTS_UDP='443,19294-19344,50000-50100'
			set $cfgname.config.NFQWS2_OPT="
				--comment=Strategy__zm_exp
				--blob=quic_google:@/opt/zapret2/files/fake/quic_initial_www_google_com.bin
				--blob=quic_4pda:@/opt/zapret2/files/fake/quic_initial_4pda_to.bin
				--blob=tls_google:@/opt/zapret2/files/fake/tls_clienthello_www_google_com.bin
				--blob=tls_max:@/opt/zapret2/files/fake/tls_clienthello_max_ru.bin
				--blob=stun2_fake:@/opt/zapret2/files/fake/stun2.bin
				--blob=discord_udp:@/opt/zapret2/files/fake/ACTIVE_DISCORD_UDP.bin
				--blob=game_udp:@/opt/zapret2/files/fake/ACTIVE_GAME_UDP.bin
				--filter-tcp=2053,2083,2087,2096,8443 --filter-l7=tls --hostlist-domains=discord.media --payload=tls_client_hello --lua-desync=fake:blob=tls_google:repeats=8:tcp_ts=-600000:tcp_ts_up --lua-desync=multisplit:pos=1:seqovl=681:seqovl_pattern=tls_google
				--new
				--filter-tcp=443 --filter-l7=tls --hostlist=/opt/zapret2/ipset/zapret-hosts-google.txt --payload=tls_client_hello --lua-desync=hostfakesplit:host=www.google.com:ip_id=zero:tcp_ts=-600000:tcp_ts_up
				--new
				--filter-tcp=80,443 --filter-l7=http,tls <HOSTLIST> --payload=tls_client_hello --lua-desync=fake:blob=tls_max:repeats=4:tcp_ts=-600000:tcp_ts_up --lua-desync=multisplit:pos=1:seqovl=480:seqovl_pattern=stun2_fake --payload=http_req --lua-desync=fake:blob=tls_max:repeats=4:tcp_ts=-600000:tcp_ts_up --lua-desync=multisplit:pos=1:seqovl=480:seqovl_pattern=stun2_fake
				--new
				--filter-udp=443 --filter-l7=quic <HOSTLIST_NOAUTO> --payload=quic_initial --lua-desync=fake:blob=quic_google:repeats=11
				--new
				--filter-udp=19294-19344,50000-50100 --filter-l7=discord,stun,unknown --payload=discord_ip_discovery --lua-desync=fake:blob=quic_google:repeats=4 --lua-desync=fake:blob=discord_udp:repeats=4 --payload=stun --lua-desync=fake:blob=discord_udp:repeats=4 --payload=unknown --lua-desync=fake:blob=quic_google:payload=unknown:repeats=4 --lua-desync=fake:blob=discord_udp:payload=unknown:repeats=4
			"
			commit $cfgname
		EOF
	fi
	return 0
}

function set_cfg_default_values
{
	local opt_flags=${1:--}
	local opt_strat=${2:-default}
	local cfgname=${3:-$ZAPRET_CFG_NAME}

	local ws_user="$( uci -q get $cfgname.config.WS_USER )"
	if ! echo "$opt_flags" | grep -q "(skip_base)" || [ -z "$ws_user" ]; then
		set_cfg_reset_values $cfgname
	fi
	if [ "$opt_strat" != "-" ]; then
		set_cfg_nfqws_strat "$opt_strat" $cfgname
	fi
	if echo "$opt_flags" | grep -q "(set_mode_autohostlist)"; then
		uci batch <<-EOF
			set $cfgname.config.MODE_FILTER='autohostlist'
			commit $cfgname
		EOF
	fi
	if echo "$opt_flags" | grep -q "(enable_custom_d)"; then
		uci batch <<-EOF
			set $cfgname.config.DISABLE_CUSTOM='0'
			commit $cfgname
		EOF
	fi
	if echo "$opt_flags" | grep -q "(disable_custom_d)"; then
		uci batch <<-EOF
			set $cfgname.config.DISABLE_CUSTOM='1'
			commit $cfgname
		EOF
	fi
	return 0
}
