include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-modemwebui
PKG_VERSION:=1.0
PKG_RELEASE:=1

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)

include $(INCLUDE_DIR)/package.mk

define Package/$(PKG_NAME)
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=Modem Web UI Interface
  DEPENDS:=+luci-base +luci-compat + tom_modem
  PKGARCH:=-compat
  PKGARCH:=all
endef

include $(TOPDIR)/feeds/luci/luci.mk

define Package/$(PKG_NAME)/description
	modemwebui scripts
endef


define Build/Compile
endef

define Package/$(PKG_NAME)/install
	# 安装 LuCI 文件
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/controller
	$(INSTALL_DATA) ./luasrc/controller/modemwebui.lua $(1)/usr/lib/lua/luci/controller/
    
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/view/modemwebui
	$(INSTALL_DATA) ./luasrc/view/modemwebui/modemwebui.htm $(1)/usr/lib/lua/luci/view/modemwebui/	
	
	# 创建目标目录
	$(INSTALL_DIR) $(1)/www/webui
	
	# 使用 CP 命令拷贝整个目录
	$(CP) ./www/webui $(1)/www

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files//etc/init.d/modemwebui $(1)/etc/init.d/modemwebui
endef


define Package/$(PKG_NAME)/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {     
 # 仅在实际设备上运行     
 /etc/init.d/modemwebui enable     
 /etc/init.d/modemwebui start     
 exit 0 
} 
endef


$(eval $(call BuildPackage,$(PKG_NAME)))