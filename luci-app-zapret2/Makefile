#
# Copyright (c) 2024 remittor
#

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-zapret2
PKG_VERSION:=1.0.5.2
PKG_RELEASE:=1
PKG_LICENSE:=MIT
PKG_MAINTAINER:=remittor <https://github.com/remittor>

LUCI_TITLE:=LuCI support for zapret2
LUCI_DEPENDS:=+zapret2
LUCI_PKGARCH:=all

define Package/$(PKG_NAME)/postinst
#!/bin/sh
if [ -z "$${IPKG_INSTROOT}" ]; then
	rm -f /tmp/luci-index*
	rm -rf /tmp/luci-modulecache/
	/etc/init.d/rpcd reload
	[ -f "/sbin/luci-reload" ] && /sbin/luci-reload
	[ -f "/etc/init.d/uhttpd" ] && /etc/init.d/uhttpd reload
	if [ -f "/opt/zapret2/restore-def-cfg.sh" ]; then
		/opt/zapret2/restore-def-cfg.sh sync flowseal_general 2>/dev/null || true
	fi
	chmod 755 /opt/zapret2/*.sh 2>/dev/null || true
fi
exit 0
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
