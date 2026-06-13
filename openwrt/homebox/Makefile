# SPDX-License-Identifier: MIT

include $(TOPDIR)/rules.mk

PKG_NAME:=homebox
PKG_VERSION:=0.1.1
PKG_RELEASE:=1

PKG_MAINTAINER:=XGHeaven <xgheaven@gmail.com>
PKG_LICENSE:=MIT

include $(INCLUDE_DIR)/package.mk

define Package/homebox
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=Web Servers/Proxies
  TITLE:=Home LAN network speed test toolbox
  URL:=https://github.com/ZASENJC/homebox-apk
  DEPENDS:=+libgcc
  USERID:=homebox:homebox
endef

define Package/homebox/description
Homebox is a browser-based home LAN network test toolbox with ping,
download, upload, and sustained throughput test modes.
endef

define Package/homebox/conffiles
/etc/config/homebox
/etc/firewall.homebox
endef

define Build/Prepare
	$(INSTALL_DIR) $(PKG_BUILD_DIR)
	[ -n "$(HOMEBOX_PREBUILT)" ] || { echo "HOMEBOX_PREBUILT must point to a prebuilt homebox binary" >&2; exit 1; }
	[ -f "$(HOMEBOX_PREBUILT)" ] || { echo "HOMEBOX_PREBUILT does not exist: $(HOMEBOX_PREBUILT)" >&2; exit 1; }
	$(INSTALL_BIN) "$(HOMEBOX_PREBUILT)" $(PKG_BUILD_DIR)/homebox
endef

define Build/Compile
endef

define Package/homebox/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/homebox $(1)/usr/bin/
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/homebox.config $(1)/etc/config/homebox
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/homebox.init $(1)/etc/init.d/homebox
	$(INSTALL_DIR) $(1)/etc
	$(INSTALL_BIN) ./files/homebox.firewall $(1)/etc/firewall.homebox
endef

$(eval $(call BuildPackage,homebox))
