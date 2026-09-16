'use strict';
'require fs';
'require form';
'require tools.widgets as widgets';
'require uci';
'require ui';
'require view';
'require view.zapret2.tools as tools';

document.head.appendChild(E('link', {
    rel: 'stylesheet',
    href: L.resource('view/zapret2/styles.css')
}));

return view.extend({
    svc_info: null,

    load: function()
    {
        return tools.baseLoad(this, (data) => {
            //console.log('SYS FEATURES: '+JSON.stringify(data.sys_feat));
            tools.load_feat_env();
            return data;
        });
    },

    render: function(data)
    {
        if (!data) {
            return;
        }
        this.svc_info = data.svc_info;
        tools.execDefferedAction(this.svc_info);

        let m, s, o, tabname;

        m = new form.Map(tools.appName, tools.AppName + ' - ' + _('Settings'));

        s = m.section(form.NamedSection, 'config');
        s.anonymous = true;
        s.addremove = false;

        /* Main settings tab */

        tabname = 'main_settings'; 
        s.tab(tabname, _('Main settings'));

        o = s.taboption(tabname, form.ListValue, 'FWTYPE', _('FWTYPE'));
        o.value('nftables', 'nftables');
        //o.value('iptables', 'iptables');
        //o.value('ipfw',     'ipfw');

        o = s.taboption(tabname, form.Flag, 'POSTNAT', _('POSTNAT'));
        o.rmempty = false;
        o.default = 1;

        o = s.taboption(tabname, form.ListValue, 'FLOWOFFLOAD', _('FLOWOFFLOAD'));
        o.value('donttouch', 'donttouch');
        o.value('none',      'none');
        o.value('software',  'software');
        o.value('hardware',  'hardware');

        o = s.taboption(tabname, form.Flag, 'INIT_APPLY_FW', _('INIT_APPLY_FW'));
        o.rmempty = false;
        o.default = 0;

        o = s.taboption(tabname, form.Flag, 'DISABLE_IPV4', _('DISABLE_IPV4'));
        o.rmempty = false;
        o.default = 1;

        o = s.taboption(tabname, form.Flag, 'DISABLE_IPV6', _('DISABLE_IPV6'));
        o.rmempty = false;
        o.default = 0;

        o = s.taboption(tabname, form.Flag, 'FILTER_TTL_EXPIRED_ICMP', 'FILTER_TTL_EXPIRED_ICMP');
        o.rmempty = false;
        o.default = 1;

        //o = s.taboption(tabname, form.ListValue, 'MODE_FILTER', _('MODE_FILTER'));
        //o.value('none',         'none');
        //o.value('ipset',        'ipset');
        //o.value('hostlist',     'hostlist');
        //o.value('autohostlist', 'autohostlist');

        o = s.taboption(tabname, form.Value, 'WS_USER', _('WS_USER'));
        o.rmempty  = false;
        o.datatype = 'string';

        o = s.taboption(tabname, form.Flag, 'DAEMON_LOG_ENABLE', _('DAEMON_LOG_ENABLE'));
        o.rmempty = false;
        o.default = 0;

        let current_size = uci.get(tools.appName, 'config', 'DAEMON_LOG_SIZE_MAX') || '0';
        let has_valid_value = false;
        let size_list = [ 500, 1000, 1500, 2000, 2500, 3000, 4000, 5000, 7000 ];
        if (current_size && current_size != '0') {
            try {
                current_size = parseInt(current_size, 10); 
                if (!isNaN(current_size) && current_size > 0) {
                    has_valid_value = true;
                    if (!size_list.includes(current_size)) {
                        size_list.push(current_size);
                        size_list.sort((a, b) => a - b);
                    }
                }
            } catch(e) {
                has_valid_value = false;
            }    
        }
        o = s.taboption(tabname, form.ListValue, 'DAEMON_LOG_SIZE_MAX', _('DAEMON_LOG_SIZE_MAX'));
        o.rmempty = false;
        if (!has_valid_value) {
            o.value('', '');
            o.default = '';
        }
        for (let idx = 0; idx < size_list.length; idx++) {
            let fsize = size_list[idx];
            o.value('' + fsize, fsize + ' KB');
            if (has_valid_value && fsize === current_size) {
                o.default = '' + fsize;
            }
        }
        o.validate = function(section_id, value) {
            if (!value || value === '') {
                return _('Please select maximum log size');
            }
            return true;
        };

        /* NFQWS_OPT_DESYNC tab */

        tabname = 'nfqws_params';
        if (tools.appName == 'zapret2') {
            s.tab(tabname, _('NFQWS2 options'));
        } else {
            s.tab(tabname, _('NFQWS options'));
        }

        let add_delim = function(sec, url = null) {
            let o = sec.taboption(tabname, form.DummyValue, '_hr');
            o.rawhtml = true;
            o.default = '<hr style="width: 620px; height: 1px; margin: 1px 0 1px; border-top: 1px solid;">';
            if (url) {
                o.default += '<br/>' + _('Help') + ': <a target=_blank href=%s>%s</a>'.format(url);
            }
        };

        let add_param = function(sec, param, locname = null, rows = 10, multiline = false) {
            if (!locname)
                locname = param;
            let btn = sec.taboption(tabname, form.Button, '_' + param + '_btn', locname);
            btn.inputtitle = _('Edit');
            btn.inputstyle = 'edit btn';
            let val = sec.taboption(tabname, form.TextValue, '_' + param);
            val.readonly = true;
            val.rows = rows + 5;
            val.wrap = false;
            val.cfgvalue = function(section_id) {
                let value = uci.get(tools.appName, section_id, param);
                if (value == null) {
                    return "";
                }
                value = value.trim();
                if (multiline == 2) {
                    value = value.replace(/\n  --/g, "\n--");
                    value = value.replace(/\n --/g, "\n--");
                    value = value.replace(/ --/g, "\n--");
                }
                return value;
            };
            val.validate = function(section_id, value) {
                return true;
            };
            let desc = locname;
            if (multiline == 2) {
                desc += '<br/>' + _('Example') + ': <a target=_blank href=%s>%s</a>'.format(tools.nfqws_opt_url);
            }
            btn.onclick = () => new tools.longstrEditDialog({
                cfgsec: 'config',
                cfgparam: param,
                title: param,
                desc: desc,
                rows: rows,
                multiline: multiline,
            }).show();
        };

        if (tools.appName == 'zapret2') {
            o = s.taboption(tabname, form.Flag, 'NFQWS2_ENABLE', _('NFQWS2_ENABLE'));
        } else {
            o = s.taboption(tabname, form.Flag, 'NFQWS_ENABLE', _('NFQWS_ENABLE'));
        }
        o.rmempty = false;
        o.default = 1;

        o = s.taboption(tabname, form.Value, 'DESYNC_MARK', _('DESYNC_MARK'));
        //o.description = _("nfqws option for DPI desync attack");
        o.rmempty     = false;
        o.datatype    = 'string';

        o = s.taboption(tabname, form.Value, 'DESYNC_MARK_POSTNAT', _('DESYNC_MARK_POSTNAT'));
        //o.description = _("nfqws option for DPI desync attack");
        o.rmempty     = false;
        o.datatype    = 'string';

        o = s.taboption(tabname, form.Value, 'FILTER_MARK', _('FILTER_MARK'));
        o.rmempty     = false;
        o.validate = function(section_id, value) { return true; };
        o.write = function(section_id, value) { return form.Value.prototype.write.call(this, section_id, (value == null || value.trim() == '') ? "\t" : value.trim()); };
        
        if (tools.appName == 'zapret2') {
            o = s.taboption(tabname, form.Value, 'NFQWS2_PORTS_TCP', _('NFQWS2_PORTS_TCP'));
        } else {
            o = s.taboption(tabname, form.Value, 'NFQWS_PORTS_TCP', _('NFQWS_PORTS_TCP'));
        }
        o.rmempty     = false;
        o.datatype    = 'string';

        if (tools.appName == 'zapret2') {
            o = s.taboption(tabname, form.Value, 'NFQWS2_PORTS_UDP', _('NFQWS2_PORTS_UDP'));
        } else {
            o = s.taboption(tabname, form.Value, 'NFQWS_PORTS_UDP', _('NFQWS_PORTS_UDP'));
        }
        o.rmempty     = false;
        o.datatype    = 'string';

        if (tools.appName == 'zapret2') {
            o = s.taboption(tabname, form.Value, 'NFQWS2_TCP_PKT_OUT', _('NFQWS2_TCP_PKT_OUT'));
        } else {
            o = s.taboption(tabname, form.Value, 'NFQWS_TCP_PKT_OUT', _('NFQWS_TCP_PKT_OUT'));
        }
        o.rmempty     = false;
        o.datatype    = 'string';

        if (tools.appName == 'zapret2') {
            o = s.taboption(tabname, form.Value, 'NFQWS2_TCP_PKT_IN', _('NFQWS2_TCP_PKT_IN'));
        } else {
            o = s.taboption(tabname, form.Value, 'NFQWS_TCP_PKT_IN', _('NFQWS_TCP_PKT_IN'));
        }
        o.rmempty     = false;
        o.datatype    = 'string';

        if (tools.appName == 'zapret2') {
            o = s.taboption(tabname, form.Value, 'NFQWS2_UDP_PKT_OUT', _('NFQWS2_UDP_PKT_OUT'));
        } else {
            o = s.taboption(tabname, form.Value, 'NFQWS_UDP_PKT_OUT', _('NFQWS_UDP_PKT_OUT'));
        }
        o.rmempty     = false;
        o.datatype    = 'string';

        if (tools.appName == 'zapret2') {
            o = s.taboption(tabname, form.Value, 'NFQWS2_UDP_PKT_IN', _('NFQWS2_UDP_PKT_IN'));
        } else {
            o = s.taboption(tabname, form.Value, 'NFQWS_UDP_PKT_IN', _('NFQWS_UDP_PKT_IN'));
        }
        o.rmempty     = false;
        o.datatype    = 'string';

        if (tools.appName == 'zapret2') {
            o = s.taboption(tabname, form.Value, 'NFQWS2_PORTS_TCP_KEEPALIVE', _('NFQWS2_PORTS_TCP_KEEPALIVE'));
        } else {
            o = s.taboption(tabname, form.Value, 'NFQWS_PORTS_TCP_KEEPALIVE', _('NFQWS_PORTS_TCP_KEEPALIVE'));
        }
        o.rmempty     = false;
        o.datatype    = 'uinteger';

        if (tools.appName == 'zapret2') {
            o = s.taboption(tabname, form.Value, 'NFQWS2_PORTS_UDP_KEEPALIVE', _('NFQWS2_PORTS_UDP_KEEPALIVE'));
        } else {
            o = s.taboption(tabname, form.Value, 'NFQWS_PORTS_UDP_KEEPALIVE', _('NFQWS_PORTS_UDP_KEEPALIVE'));
        }
        o.rmempty     = false;
        o.datatype    = 'uinteger';

        add_delim(s);

        o = s.taboption(tabname, form.ListValue, '_strat_selector', _('Preset Strategy / Auto-Rotation'));
        o.description = _('Select an anti-DPI strategy preset. "z2-ready-05" is verified to fix YouTube 4K and Discord without TLS protocol errors.');
        o.value('-', _('-- Select Strategy Preset to Apply --'));
        o.value('z2_ready_05', '⚡ ' + _('z2-ready-05 (Multisplit sequence overlap - Fix YouTube & Discord)'));
        o.value('zm_games', '🎮 ' + _('Zapret-Manager Game Filter (Warzone, Apex, Battlefield, Roblox, Steam, EA)'));
        o.value('zm_discord_media', '🎙️ ' + _('Zapret-Manager Discord Voice & Media (QUIC/STUN 50000+)'));
        o.value('zm_yv01', '▶️ ' + _('Zapret-Manager Yv01 (Google TLS Fake + Multisplit seqovl=681)'));
        o.value('zm_yv02', '▶️ ' + _('Zapret-Manager Yv02 (Multisplit pos=1,sniext+1 seqovl=1)'));
        o.value('zm_yv03', '▶️ ' + _('Zapret-Manager Yv03 (Hex 0x0F Fake + Multisplit seqovl=620)'));
        o.value('zm_yv08', '▶️ ' + _('Zapret-Manager Yv08 (Hostfakesplit google.com tcp_ts=-600000)'));
        o.value('zm_yv16', '▶️ ' + _('Zapret-Manager Yv16 (Multisplit pos=1,sniext+1 badsum)'));
        o.value('zm_yv24', '▶️ ' + _('Zapret-Manager Yv24 (STUN Fake badsum + Multisplit seqovl=654)'));
        o.value('zm_alt', '⚡ ' + _('Zapret-Manager ALT (Fake + Fakedsplit ts)'));
        o.value('zm_alt2', '⚡ ' + _('Zapret-Manager ALT2 (Multisplit seqovl=652 pos=2)'));
        o.value('zm_alt3', '⚡ ' + _('Zapret-Manager ALT3 (Fake ya.ru + Hostfakesplit ts)'));
        o.value('zm_alt4', '⚡ ' + _('Zapret-Manager ALT4 (Fake badseq 1000 + Multisplit)'));
        o.value('zm_alt4_mod_maximusng', '⚡ ' + _('Zapret-Manager ALT4 mod MaximusNG'));
        o.value('zm_alt5', '⚡ ' + _('Zapret-Manager ALT5 (Syndata + Multidisorder)'));
        o.value('zm_alt6', '⚡ ' + _('Zapret-Manager ALT6 (Multisplit seqovl=681 pos=1)'));
        o.value('zm_alt7', '⚡ ' + _('Zapret-Manager ALT7 (Multisplit pos=2,sniext+1 seqovl=679)'));
        o.value('zm_alt8', '⚡ ' + _('Zapret-Manager ALT8 (Fake badseq +2)'));
        o.value('zm_alt9', '⚡ ' + _('Zapret-Manager ALT9 (Hostfakesplit ts+md5sig)'));
        o.value('zm_alt10', '⚡ ' + _('Zapret-Manager ALT10 (Fake 4pda ts)'));
        o.value('zm_alt11', '⚡ ' + _('Zapret-Manager ALT11 (Fake stun2 + Multisplit seqovl=664)'));
        o.value('zm_alt12', '⚡ ' + _('Zapret-Manager ALT12 (ALT11 + Google Hostfakesplit)'));
        o.value('zm_alt13', '⚡ ' + _('Zapret-Manager ALT13 (Fake + Hostfakesplit mail.ru ts)'));
        o.value('zm_exp', '⚡ ' + _('Zapret-Manager EXP (Fake + Multisplit seqovl=480 stun2)'));
        o.value('zm_fake_tls_auto', '⚡ ' + _('Zapret-Manager FAKE TLS AUTO (Fake + Multidisorder 1,midsld)'));
        o.value('zm_fake_tls_auto_alt', '⚡ ' + _('Zapret-Manager FAKE TLS AUTO ALT (Fake + Fakedsplit pos=1)'));
        o.value('zm_fake_tls_auto_alt2', '⚡ ' + _('Zapret-Manager FAKE TLS AUTO ALT2 (Fake + Multisplit badseq)'));
        o.value('zm_fake_tls_auto_alt3', '⚡ ' + _('Zapret-Manager FAKE TLS AUTO ALT3 (Fake + Multisplit ts)'));
        o.value('zm_simple_fake', '⚡ ' + _('Zapret-Manager SIMPLE FAKE (Fake Google + ts)'));
        o.value('zm_simple_fake_alt', '⚡ ' + _('Zapret-Manager SIMPLE FAKE ALT (Fake badseq +2)'));
        o.value('zm_simple_fake_alt2', '⚡ ' + _('Zapret-Manager SIMPLE FAKE ALT2 (Fake max.ru ts)'));
        o.value('zm_martin_backer', '⚡ ' + _('Zapret-Manager MartinBacker (Circular Multi-strategy)'));
        o.value('zm_krushaaa', '⚡ ' + _('Zapret-Manager Krushaaa (BurgerKing + Magnit + ts)'));
        o.value('zm_hardcorp74', '⚡ ' + _('Zapret-Manager Hardcorp74'));
        o.value('zm_eduncey', '⚡ ' + _('Zapret-Manager Eduncey'));
        o.value('zm_uvvi2', '⚡ ' + _('Zapret-Manager Uvvi2 (Targeted Voice + Circular)'));
        o.value('flowseal_general', '🔥 ' + _('Flowseal Classic (YouTube 4K + Discord Voice)'));
        o.value('youtube_discord_ultimate', '🎯 ' + _('YouTube & Discord Ultimate'));
        o.value('z2_ready_06', '🛡️ ' + _('z2-ready-06 (Multidisorder SNI split)'));
        o.value('z2_ready_01', '⚙️ ' + _('z2-ready-01 (Default fake + disorder)'));
        o.value('z2_ready_02', '⚙️ ' + _('z2-ready-02 (Google TLS fake + disorder)'));
        o.value('z2_ready_03', '⚙️ ' + _('z2-ready-03 (Timestamp fake + multisplit)'));
        o.value('z2_ready_04', '⚙️ ' + _('z2-ready-04 (MD5 fake + multisplit)'));
        o.value('z2_ready_07', '⚙️ ' + _('z2-ready-07 (TCP segment overlap + drop)'));
        o.value('z2_ready_08', '⚙️ ' + _('z2-ready-08 (Window size + disorder)'));
        o.value('z2_ready_09', '⚙️ ' + _('z2-ready-09 (Repeated fake + multisplit)'));
        o.value('z2_ready_10', '⚙️ ' + _('z2-ready-10 (Repeated fake + multidisorder)'));
        o.value('flowseal_fake_tls_auto', '🚀 ' + _('Flowseal Fake TLS Auto (YouTube + Discord + General)'));
        o.value('flowseal_simple_fake', '🍃 ' + _('Flowseal Simple Fake (Low CPU)'));
        o.value('z2k_autocircular', '⚡ ' + _('Z2K Auto-Rotation (Автоподбор стратегий при сбоях)'));
        o.value('remittor_168', '🛡️ ' + _('Remittor #168 (with DoT DNS TCP 853)'));
        o.value('v1_by_Schiz23', 'v1 by Schiz23');
        o.value('v2_by_Schiz23', 'v2 by Schiz23');
        o.value('default', _('Default'));
        o.default = '-';

        let btn_apply_strat = s.taboption(tabname, form.Button, '_apply_strat_btn', _('Apply Strategy'));
        btn_apply_strat.inputtitle = _('Apply & Reload Strategy');
        btn_apply_strat.inputstyle = 'btn cbi-button-action';
        btn_apply_strat.description = _('Immediately applies the selected strategy preset and reloads Zapret2');
        btn_apply_strat.onclick = () => {
            let sel = document.querySelector('select[id*="_strat_selector"]');
            let val = sel ? sel.value : '-';
            if (!val || val === '-') {
                ui.addNotification(null, E('p', _('Please select a strategy preset from the dropdown first.')));
                return;
            }
            ui.addNotification(null, E('p', _('Applying strategy "%s", please wait...').format(val)));
            return fs.exec('/opt/zapret2/restore-def-cfg.sh', [ '(skip_base)(sync)', val ]).then(res => {
                if (res.code == 0) {
                    ui.addNotification(null, E('p', _('Strategy "%s" applied successfully! Reloading service...').format(val)));
                    return fs.exec('/etc/init.d/zapret2', [ 'restart' ]).then(() => {
                        setTimeout(() => location.reload(), 1500);
                    });
                } else {
                    ui.addNotification(null, E('p', _('Failed to apply strategy: ') + (res.stderr || res.stdout || '')));
                }
            });
        };

        let btn_autotune = s.taboption(tabname, form.Button, '_autotune_btn', _('Auto-Tune (Автоподбор стратегий)'));
        btn_autotune.inputtitle = '⚡ ' + _('Запустить автоподбор стратегии');
        btn_autotune.inputstyle = 'btn cbi-button-apply';
        btn_autotune.description = _('Автоматически тестирует проверенные профили на YouTube, Discord и заблокированных сервисах и применяет наилучшую рабочую стратегию.');
        btn_autotune.onclick = () => {
            ui.showModal(_('Автоподбор стратегий Zapret2'), [
                E('p', { class: 'spinning' }, _('Запуск тестирования... Проверка доступности сервисов и подбор лучшей стратегии.')),
                E('pre', { id: 'autotune-log-box', style: 'max-height: 280px; overflow-y: auto; background: #1a1a1a; color: #33ff33; padding: 10px; border-radius: 4px; font-family: monospace; font-size: 12px;' }, _('Подготовка изолированного тестового окружения...')),
                E('div', { class: 'right', style: 'margin-top: 15px;' }, [
                    E('button', {
                        class: 'btn',
                        id: 'autotune-close-btn',
                        disabled: true,
                        click: () => location.reload()
                    }, _('Закрыть'))
                ])
            ]);

            fs.exec('/opt/zapret2/autotune.sh', [ 'auto' ]);

            let pollInterval = setInterval(() => {
                fs.read('/tmp/zapret2_autotune.log').then(content => {
                    let box = document.getElementById('autotune-log-box');
                    if (box && content) {
                        box.textContent = content;
                        box.scrollTop = box.scrollHeight;
                    }
                });

                fs.read('/tmp/zapret2_autotune.json').then(jsonStr => {
                    if (jsonStr) {
                        try {
                            let st = JSON.parse(jsonStr);
                            if (st && st.running === false) {
                                clearInterval(pollInterval);
                                let closeBtn = document.getElementById('autotune-close-btn');
                                if (closeBtn) {
                                    closeBtn.disabled = false;
                                    closeBtn.className = 'btn cbi-button-action';
                                    closeBtn.textContent = _('Применить и обновить страницу');
                                }
                                if (st.best) {
                                    ui.addNotification(null, E('p', _('Автоподбор завершен! Победитель: %s. Стратегия успешно применена.').format(st.best.title)));
                                } else {
                                    ui.addNotification(null, E('p', _('Автоподбор завершен, рабочая стратегия не найдена.')));
                                }
                            }
                        } catch (e) {}
                    }
                });
            }, 1200);
        };

        add_delim(s, tools.nfqws_opt_url);
        if (tools.appName == 'zapret2') {
            add_param(s, 'NFQWS2_OPT', null, 21, 2);
        } else {
            add_param(s, 'NFQWS_OPT', null, 21, 2);
        }
        
        /* AutoHostList settings */

        tabname = 'autohostlist_tab'; 
        s.tab(tabname, _('AutoHostList'));

        o = s.taboption(tabname, form.Flag, 'MODE_FILTER', _('Use AutoHostList mode'));
        o.rmempty = false;
        o.default = '0';
        o.validate = function(section_id, value) { return true; };
        o.load = function(section_id) {
            return uci.load(tools.appName).then(L.bind(function() {
                var v = uci.get(tools.appName, section_id, 'MODE_FILTER');
                return (v === 'autohostlist') ? '1' : '0';
            }, this));
        };
        o.write = function(section_id, value) {
            return uci.set(tools.appName, section_id, 'MODE_FILTER', value === '1' ? 'autohostlist' : 'hostlist');
        };

        if (tools.appName == 'zapret2') {
            o = s.taboption(tabname, form.Value, 'AUTOHOSTLIST_INCOMING_MAXSEQ', _('INCOMING_MAXSEQ'));
            o.rmempty     = false;
            o.datatype    = 'uinteger';

            o = s.taboption(tabname, form.Value, 'AUTOHOSTLIST_RETRANS_MAXSEQ', _('RETRANS_MAXSEQ'));
            o.rmempty     = false;
            o.datatype    = 'uinteger';

            o = s.taboption(tabname, form.Value, 'AUTOHOSTLIST_RETRANS_RESET', _('RETRANS_RESET'));
            o.rmempty     = false;
            o.datatype    = 'uinteger';
        }
        
        o = s.taboption(tabname, form.Value, 'AUTOHOSTLIST_RETRANS_THRESHOLD', _('RETRANS_THRESHOLD'));
        o.rmempty     = false;
        o.datatype    = 'uinteger';

        o = s.taboption(tabname, form.Value, 'AUTOHOSTLIST_FAIL_THRESHOLD', _('FAIL_THRESHOLD'));
        o.rmempty     = false;
        o.datatype    = 'uinteger';

        o = s.taboption(tabname, form.Value, 'AUTOHOSTLIST_FAIL_TIME', _('FAIL_TIME'));
        o.rmempty     = false;
        o.datatype    = 'uinteger';

        if (tools.appName == 'zapret2') {
            o = s.taboption(tabname, form.Value, 'AUTOHOSTLIST_UDP_IN', _('UDP_IN'));
            o.rmempty     = false;
            o.datatype    = 'uinteger';

            o = s.taboption(tabname, form.Value, 'AUTOHOSTLIST_UDP_OUT', _('UDP_OUT'));
            o.rmempty     = false;
            o.datatype    = 'uinteger';
        }

        o = s.taboption(tabname, form.Button, '_auto_host_btn', _('Auto host list entries'));
        o.inputtitle = _('Edit');
        o.inputstyle = 'edit btn';
        o.description = tools.autoHostListFN;
        o.onclick = () => new tools.fileEditDialog({
            file: tools.autoHostListFN,
            title: _('Auto host list'),
            desc: '',
            rows: 15,
        }).show();

        o = s.taboption(tabname, form.Flag, 'AUTOHOSTLIST_DEBUGLOG', _('DEBUGLOG'));
        o.rmempty     = false;
        o.default     = 0;

        o = s.taboption(tabname, form.Button, '_auto_host_debug_btn', _('Auto host debug list entries'));
        o.inputtitle = _('Edit');
        o.inputstyle = 'edit btn';
        o.description = tools.autoHostListDbgFN;
        o.onclick = () => new tools.fileEditDialog({
            file: tools.autoHostListDbgFN,
            title: _('Auto host debug list'),
            desc: '',
            rows: 15,
        }).show();
        
        /* HostList settings */

        tabname = 'hostlist_tab'; 
        s.tab(tabname, _('Host lists'));

        o = s.taboption(tabname, form.Button, '_google_entries_btn', _('Google hostname entries'));
        o.inputtitle = _('Edit');
        o.inputstyle = 'edit btn';
        o.description = tools.hostsGoogleFN;
        o.onclick = () => new tools.fileEditDialog({
            file: tools.hostsGoogleFN,
            title: _('Google hostname entries'),
            desc: _('One hostname per line.<br />Examples:'),
            aux: '<code>youtube.com<br />googlevideo.com</code>',
            rows: 15,
        }).show();

        o = s.taboption(tabname, form.Button, '_user_entries_btn', _('User hostname entries <HOSTLIST>'));
        o.inputtitle = _('Edit');
        o.inputstyle = 'edit btn';
        o.description = tools.hostsUserFN;
        o.onclick = () => new tools.fileEditDialog({
            file: tools.hostsUserFN,
            title: _('User entries'),
            desc: _('One hostname per line.<br />Examples:'),
            aux: '<code>domain.net<br />sub.domain.com<br />facebook.com</code>',
            rows: 15,
        }).show();

        o = s.taboption(tabname, form.Button, '_user_excluded_entries_btn', _('User excluded hostname entries'));
        o.inputtitle = _('Edit');
        o.inputstyle = 'edit btn';
        o.description = tools.hostsUserExcludeFN;
        o.onclick = () => new tools.fileEditDialog({
            file: tools.hostsUserExcludeFN,
            title: _('User excluded entries'),
            desc: _('One hostname per line.<br />Examples:'),
            aux: '<code>domain.net<br />sub.domain.com<br />gosuslugi.ru</code>',
            rows: 15,
        }).show();
        
        add_delim(s);

        o = s.taboption(tabname, form.Button, '_ip_exclude_filter_btn', _('Excluded IP entries'));
        o.inputtitle = _('Edit');
        o.inputstyle = 'edit btn';
        o.description = tools.iplstExcludeFN;
        o.onclick = () => new tools.fileEditDialog({
            file: tools.iplstExcludeFN,
            title: _('Excluded IP filter'),
            desc: _('Patterns can be strings or regular expressions. Each pattern in a separate line<br />Examples:'),
            aux: '<code>128.199.0.0/16<br />34.217.90.52<br />162.13.190.77</code>',
            rows: 15,
        }).show();

        o = s.taboption(tabname, form.Button, '_user_ip_filter_btn', _('User IP entries'));
        o.inputtitle = _('Edit');
        o.inputstyle = 'edit btn';
        o.description = tools.iplstUserFN;
        o.onclick = () => new tools.fileEditDialog({
            file: tools.iplstUserFN,
            title: _('User IP filter'),
            desc: _('Patterns can be strings or regular expressions. Each pattern in a separate line<br />Examples:'),
            aux: '<code>128.199.0.0/16<br />34.217.90.52<br />162.13.190.77</code>',
            rows: 15,
        }).show();

        o = s.taboption(tabname, form.Button, '_user_excluded_ip_filter_btn', _('User excluded IP entries'));
        o.inputtitle = _('Edit');
        o.inputstyle = 'edit btn';
        o.description = tools.iplstUserExcludeFN;
        o.onclick = () => new tools.fileEditDialog({
            file: tools.iplstUserExcludeFN,
            title: _('User excluded IP filter'),
            desc: _('Patterns can be strings or regular expressions. Each pattern in a separate line<br />Examples:'),
            aux: '<code>128.199.0.0/16<br />34.217.90.52<br />162.13.190.77</code>',
            rows: 15,
        }).show();
        
        add_delim(s);
        
        for (let num = 1; num <= tools.custFileMax; num++) {
            let fn = tools.custFileTemplate.format(num.toString());
            let name = _('Custom file #' + num);
            o = s.taboption(tabname, form.Button, '_cust_file%d_btn'.format(num), name);
            o.inputtitle = _('Edit');
            o.inputstyle = 'edit btn';
            o.description = fn;
            o.onclick = () => new tools.fileEditDialog({ file: fn, title: name, rows: 15}).show();
        }

        /* custom.d files */

        tabname = 'custom_d_tab'; 
        s.tab(tabname, 'custom.d');

        o = s.taboption(tabname, form.Flag, 'DISABLE_CUSTOM', _('Use custom.d scripts'));
        o.rmempty = false;
        o.default = '0';
        o.validate = function(section_id, value) { return true; };
        o.load = function(section_id) {
            return uci.load(tools.appName).then(L.bind(function() {
                var v = uci.get(tools.appName, section_id, 'DISABLE_CUSTOM');
                return (v === '1') ? '0' : '1';
            }, this));
        };
        o.write = function(section_id, value) {
            return uci.set(tools.appName, section_id, 'DISABLE_CUSTOM', value === '1' ? '0' : '1');
        };

        add_delim(s);
        
        for (let i = 0; i < tools.customdPrefixList.length; i++) {
            let num = tools.customdPrefixList[i];
            let fn = tools.customdFileFormat.format(num.toString());
            let name = _('custom.d script #' + num);
            o = s.taboption(tabname, form.Button, '_customd_file%d_btn'.format(num), name);
            o.inputtitle = _('Edit');
            o.inputstyle = 'edit btn';
            o.description = fn;
            let desc = '';
            if (num == tools.discord_num) {
                desc = _('Example') + ': ';
                for (let k = 0; k < tools.discord_url.length; k++) {
                    let url = tools.discord_url[k];
                    if (k > 0) desc += ' <br> ';
                    const filename = url.substring(url.lastIndexOf("/") + 1).split("?")[0];
                    desc += '<a target=_blank href=' + url + '>' + filename + '</a>';
                }
            }
            o.onclick = () => new tools.fileEditDialog({ file: fn, title: name, desc: desc, rows: 15}).show();
        }

        /* Cloudflare WARP settings */

        tabname = 'warp_tab'; 
        s.tab(tabname, _('Cloudflare WARP (Games)'));

        o = s.taboption(tabname, form.Flag, 'WARP_ENABLED', _('Enable Cloudflare WARP Tunnel'));
        o.description = _('Route Games and/or Telegram via free Cloudflare Anycast tunnel');
        o.rmempty = false;
        o.default = 0;

        o = s.taboption(tabname, form.Flag, 'WARP_GAMES', _('Route Games via WARP'));
        o.description = _('Warzone / Call of Duty, Steam, Battle.net, EA, Epic Games, Riot, etc.');
        o.rmempty = false;
        o.default = 1;
        o.depends('WARP_ENABLED', '1');

        o = s.taboption(tabname, form.Flag, 'WARP_TELEGRAM', _('Route Telegram via WARP'));
        o.description = _('Transparently route Telegram IP ranges through WARP (unblocks Telegram on all home devices)');
        o.rmempty = false;
        o.default = 1;
        o.depends('WARP_ENABLED', '1');

        o = s.taboption(tabname, form.Button, '_warp_register_btn', _('WARP Account Registration'));
        o.inputtitle = _('Register / Renew Account');
        o.inputstyle = 'btn cbi-button-action';
        o.description = _('Register free Cloudflare WARP device account directly (no card or purchase required)');
        o.onclick = () => {
            ui.addNotification(null, E('p', _('Registering free WARP account, please wait...')));
            return fs.exec('/opt/zapret2/warp.sh', [ 'register' ]).then(res => {
                if (res.code == 0) {
                    ui.addNotification(null, E('p', _('WARP device account registered successfully!')));
                } else {
                    ui.addNotification(null, E('p', _('WARP registration error: ') + (res.stdout || '') + (res.stderr || '')));
                }
            });
        };

        o = s.taboption(tabname, form.Button, '_warp_scout_btn', _('WARP Scout (Find Alive Endpoint)'));
        o.inputtitle = _('Scout Endpoint');
        o.inputstyle = 'btn cbi-button-action';
        o.description = _('Scans for unblocked Cloudflare IP endpoints with lowest latency');
        o.onclick = () => {
            ui.addNotification(null, E('p', _('Scouting endpoints for gaming latency, please wait...')));
            return fs.exec('/opt/zapret2/warp.sh', [ 'scout' ]).then(res => {
                if (res.code == 0 && res.stdout) {
                    ui.addNotification(null, E('pre', { 'style': 'font-family: monospace; white-space: pre-wrap;' }, res.stdout));
                } else {
                    ui.addNotification(null, E('p', _('Scout error: ') + (res.stderr || res.stdout || '')));
                }
            });
        };

        o = s.taboption(tabname, form.Button, '_warp_update_lists_btn', _('Update Gaming & Telegram Lists'));
        o.inputtitle = _('Update Lists Now');
        o.inputstyle = 'btn';
        o.description = _('Fetches the latest gaming IP ranges and Telegram IP ranges');
        o.onclick = () => {
            ui.addNotification(null, E('p', _('Updating gaming and Telegram IP lists...')));
            return fs.exec('/opt/zapret2/update-lists.sh', [ 'all' ]).then(res => {
                if (res.code == 0) {
                    ui.addNotification(null, E('p', _('Lists updated successfully!')));
                } else {
                    ui.addNotification(null, E('p', _('List update error: ') + (res.stderr || res.stdout || '')));
                }
            });
        };

        add_delim(s);

        o = s.taboption(tabname, form.DummyValue, '_gaming_lists_header');
        o.rawhtml = true;
        o.default = '<h3 style="margin-top: 15px; margin-bottom: 5px;">' + _('🎮 Gaming & Telegram IP Lists (Click to View / Edit)') + '</h3>';

        o = s.taboption(tabname, form.Button, '_edit_warzone_btn', _('Warzone / Call of Duty (772 subnets)'));
        o.inputtitle = _('View / Edit');
        o.inputstyle = 'edit btn';
        o.description = '/opt/zapret2/files/lists/warp/games/Warzone_CallOfDuty.txt';
        o.onclick = () => new tools.fileEditDialog({
            file: '/opt/zapret2/files/lists/warp/games/Warzone_CallOfDuty.txt',
            title: _('Warzone / Call of Duty IP CIDRs (772 subnets)'),
            desc: _('Full CIDR range list for Call of Duty Warzone servers.<br />One subnet per line.'),
            rows: 20,
        }).show();

        
        o = s.taboption(tabname, form.Button, '_edit_steam_btn', _('Steam IP Ranges'));
        o.inputtitle = _('View / Edit');
        o.inputstyle = 'edit btn';
        o.description = '/opt/zapret2/files/lists/warp/games/Steam.txt';
        o.onclick = () => new tools.fileEditDialog({
            file: '/opt/zapret2/files/lists/warp/games/Steam.txt',
            title: _('Steam Game & Voice Servers'),
            desc: _('Steam servers list.<br />One subnet per line.'),
            rows: 15,
        }).show();

        o = s.taboption(tabname, form.Button, '_edit_ea_btn', _('EA / Origin IP Ranges'));
        o.inputtitle = _('View / Edit');
        o.inputstyle = 'edit btn';
        o.description = '/opt/zapret2/files/lists/warp/games/EA_Origin.txt';
        o.onclick = () => new tools.fileEditDialog({
            file: '/opt/zapret2/files/lists/warp/games/EA_Origin.txt',
            title: _('EA & Origin Game Servers'),
            desc: _('EA/Origin servers list.<br />One subnet per line.'),
            rows: 15,
        }).show();

        o = s.taboption(tabname, form.Button, '_edit_battlenet_btn', _('Battle.net / Blizzard IP Ranges'));
        o.inputtitle = _('View / Edit');
        o.inputstyle = 'edit btn';
        o.description = '/opt/zapret2/files/lists/warp/games/BattleNet.txt';
        o.onclick = () => new tools.fileEditDialog({
            file: '/opt/zapret2/files/lists/warp/games/BattleNet.txt',
            title: _('Battle.net / Blizzard Servers'),
            desc: _('Blizzard game servers list.<br />One subnet per line.'),
            rows: 15,
        }).show();

        o = s.taboption(tabname, form.Button, '_edit_epic_btn', _('Epic Games & Fortnite IP Ranges'));
        o.inputtitle = _('View / Edit');
        o.inputstyle = 'edit btn';
        o.description = '/opt/zapret2/files/lists/warp/games/EpicGames_Fortnite.txt';
        o.onclick = () => new tools.fileEditDialog({
            file: '/opt/zapret2/files/lists/warp/games/EpicGames_Fortnite.txt',
            title: _('Epic Games & Fortnite Servers'),
            desc: _('Epic Games servers list.<br />One subnet per line.'),
            rows: 15,
        }).show();

        o = s.taboption(tabname, form.Button, '_edit_riot_btn', _('Riot Games & Valorant IP Ranges'));
        o.inputtitle = _('View / Edit');
        o.inputstyle = 'edit btn';
        o.description = '/opt/zapret2/files/lists/warp/games/RiotGames_Valorant.txt';
        o.onclick = () => new tools.fileEditDialog({
            file: '/opt/zapret2/files/lists/warp/games/RiotGames_Valorant.txt',
            title: _('Riot Games & Valorant Servers'),
            desc: _('Riot Games servers list.<br />One subnet per line.'),
            rows: 15,
        }).show();

        o = s.taboption(tabname, form.Button, '_edit_roblox_btn', _('Roblox IP Ranges'));
        o.inputtitle = _('View / Edit');
        o.inputstyle = 'edit btn';
        o.description = '/opt/zapret2/files/lists/warp/games/Roblox.txt';
        o.onclick = () => new tools.fileEditDialog({
            file: '/opt/zapret2/files/lists/warp/games/Roblox.txt',
            title: _('Roblox Game Servers'),
            desc: _('Roblox servers list.<br />One subnet per line.'),
            rows: 15,
        }).show();

        o = s.taboption(tabname, form.Button, '_edit_custom_games_btn', _('Custom Gaming IP List (User Added)'));
        o.inputtitle = _('View / Edit');
        o.inputstyle = 'edit btn';
        o.description = '/opt/zapret2/files/lists/warp/games_user.txt';
        o.onclick = () => new tools.fileEditDialog({
            file: '/opt/zapret2/files/lists/warp/games_user.txt',
            title: _('Custom Gaming IP List'),
            desc: _('Add any custom game server IP subnets you wish to route via WARP.<br />One CIDR per line.'),
            rows: 15,
        }).show();

        /* Telegram Proxy (TG WS Proxy) tab */

        tabname = 'telegram_tab';
        s.tab(tabname, _('Telegram (TG WS Proxy)'));

        o = s.taboption(tabname, form.DummyValue, '_tg_info_header');
        o.rawhtml = true;
        o.default = '<div style="background: #f0f7ff; border: 1px solid #cce3f5; border-radius: 6px; padding: 12px; margin-bottom: 15px;">' +
            '<h4 style="margin: 0 0 6px 0; color: #005fb8;">✈️ ' + _('TG WS Proxy: Telegram через Cloudflare WebSocket') + '</h4>' +
            '<p style="margin: 0; font-size: 13px; color: #333;">' +
            _('Сервис поднимает локальный SOCKS5-прокси на роутере (порт 2080) и заворачивает запросы Telegram в Cloudflare WebSockets (cf-proxy). ' +
              '<strong>Белый IP не требуется</strong> — прокси работает за любым NAT/провайдерским CGNAT. ' +
              'Для экономии памяти роутера установка производится по запросу пользователя.') +
            '</p></div>';

        let tg_status_dummy = s.taboption(tabname, form.DummyValue, '_tg_status_view');
        tg_status_dummy.rawhtml = true;
        tg_status_dummy.default = '<div id="tg_status_box" style="padding: 10px; background: #fafafa; border: 1px solid #eee; border-radius: 4px; margin-bottom: 15px;">' +
            '<span id="tg_status_indicator">⌛ ' + _('Проверка статуса TG WS Proxy...') + '</span></div>';

        let refresh_tg_status = () => {
            let elem = document.getElementById('tg_status_indicator');
            if (!elem) return Promise.resolve();
            return fs.exec('/opt/zapret2/tg_proxy.sh', [ 'status' ]).then(res => {
                if (res.code == 0 && res.stdout) {
                    try {
                        let st = JSON.parse(res.stdout);
                        if (st.running) {
                            elem.innerHTML = '<span style="color: #2e7d32; font-weight: bold; font-size: 15px;">🟢 ЗАПУЩЕН</span> — порт: ' + st.port + 
                                '<br /><br /><a class="btn cbi-button-apply" style="display:inline-block; padding: 6px 16px; text-decoration: none; font-weight: bold;" href="' + st.link + '">🔗 ' + _('Подключить в Telegram в 1 клик') + '</a>' +
                                '<br /><small style="color:#666; margin-top:5px; display:inline-block;">SOCKS5: ' + st.lan_ip + ':' + st.port + ' | Ссылка: ' + st.link + '</small>';
                        } else if (st.installed) {
                            elem.innerHTML = '<span style="color: #ed6c02; font-weight: bold; font-size: 15px;">🟡 УСТАНОВЛЕН, НО ОСТАНОВЛЕН</span>';
                        } else {
                            elem.innerHTML = '<span style="color: #666; font-weight: bold; font-size: 15px;">⚪ НЕ УСТАНОВЛЕН</span> (память роутера не расходуется)';
                        }
                    } catch(e) {
                        elem.textContent = res.stdout;
                    }
                } else {
                    elem.textContent = _('Статус: ') + (res.stderr || res.stdout || 'код ' + res.code);
                }
            }).catch(e => {
                elem.textContent = _('Ошибка связи: ') + e.message;
            });
        };

        let tg_status_btn = s.taboption(tabname, form.Button, '_tg_status_btn', _('Проверить статус'));
        tg_status_btn.inputtitle = '🔍 ' + _('Проверить статус TG WS Proxy');
        tg_status_btn.inputstyle = 'btn';
        tg_status_btn.onclick = () => {
            let elem = document.getElementById('tg_status_indicator');
            if (elem) elem.innerHTML = '⌛ ' + _('Проверка статуса...');
            return refresh_tg_status();
        };

        let tg_install_btn = s.taboption(tabname, form.Button, '_tg_install_btn', _('Установка сервиса'));
        tg_install_btn.inputtitle = '📥 ' + _('Установить TG WS Proxy');
        tg_install_btn.inputstyle = 'btn cbi-button-apply';
        tg_install_btn.description = _('Скачивает легковесный бинарник TG WS Proxy под архитектуру роутера, регистрирует сервис в procd и сразу запускает его.');
        tg_install_btn.onclick = () => {
            let elem = document.getElementById('tg_status_indicator');
            if (elem) elem.innerHTML = '⏳ <span style="color: #005fb8; font-weight: bold;">' + _('Идет установка TG WS Proxy... Пожалуйста, подождите (скачивание файла)...') + '</span>';
            return fs.exec('/opt/zapret2/tg_proxy.sh', [ 'install' ]).then(res => {
                return refresh_tg_status();
            }).catch(e => {
                if (elem) elem.textContent = _('Ошибка установки: ') + e.message;
            });
        };

        let tg_restart_btn = s.taboption(tabname, form.Button, '_tg_restart_btn', _('Перезапуск сервиса'));
        tg_restart_btn.inputtitle = '🔄 ' + _('Перезапустить TG WS Proxy');
        tg_restart_btn.inputstyle = 'btn';
        tg_restart_btn.onclick = () => {
            let elem = document.getElementById('tg_status_indicator');
            if (elem) elem.innerHTML = '⏳ ' + _('Перезапуск...');
            return fs.exec('/opt/zapret2/tg_proxy.sh', [ 'restart' ]).then(() => {
                return refresh_tg_status();
            }).catch(e => {
                if (elem) elem.textContent = _('Ошибка перезапуска: ') + e.message;
            });
        };

        let tg_remove_btn = s.taboption(tabname, form.Button, '_tg_remove_btn', _('Удаление сервиса'));
        tg_remove_btn.inputtitle = '🗑️ ' + _('Удалить TG WS Proxy (Освободить память)');
        tg_remove_btn.inputstyle = 'btn cbi-button-reset';
        tg_remove_btn.description = _('Полностью останавливает сервис и удаляет исполняемый файл для освобождения флеш-памяти.');
        tg_remove_btn.onclick = () => {
            let elem = document.getElementById('tg_status_indicator');
            if (elem) elem.innerHTML = '⏳ ' + _('Удаление сервиса...');
            return fs.exec('/opt/zapret2/tg_proxy.sh', [ 'remove' ]).then(res => {
                return refresh_tg_status();
            }).catch(e => {
                if (elem) elem.textContent = _('Ошибка удаления: ') + e.message;
            });
        };

        let map_promise = m.render();
        map_promise.then(node => {
            node.classList.add('fade-in');
            setTimeout(refresh_tg_status, 400);
        });
        map_promise.then(node => node.classList.add('fade-in'));
        return map_promise;
    },

    handleSaveApply: function(ev, mode)
    {
        return this.handleSave(ev).then(() => {
            let apply_exec = tools.checkUnsavedChanges();
            if (apply_exec) {
                ui.changes.apply(mode == '0');
                tools.setDefferedAction('restart', this.svc_info);
            } else {
                if (this.svc_info?.dmn.inited) {
                    tools.serviceActionEx('restart');
                }
            }
        });
    },
});
