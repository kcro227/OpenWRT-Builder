include $(TOPDIR)/rules.mk

# 包信息
PKG_NAME:=ubus-at-client
PKG_VERSION:=1.0
PKG_RELEASE:=1

PKG_MAINTAINER:=Your Name <your.email@example.com>
PKG_LICENSE:=MIT

include $(INCLUDE_DIR)/package.mk

# 包定义
define Package/ubus-at-client
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Ubus AT Client for communicating with AT modems
  DEPENDS:=+libubus +libubox +libblobmsg-json
endef

define Package/ubus-at-client/description
  A client application that uses ubus to communicate with AT modems
  through the ubus-at-daemon service.
endef

# 指定源代码位置
define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) ./src/* $(PKG_BUILD_DIR)/
endef

# 指定构建配置
define Build/Configure
	# 无需配置
endef

# 指定构建命令
define Build/Compile
	$(TARGET_CC) $(TARGET_CFLAGS) -I$(STAGING_DIR)/usr/include \
		-L$(STAGING_DIR)/usr/lib -lubus -lubox -lblobmsg_json \
		-o $(PKG_BUILD_DIR)/ubus-at-client \
		$(PKG_BUILD_DIR)/main.c $(PKG_BUILD_DIR)/ubus_client.c
endef

# 指定安装方法
define Package/ubus-at-client/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/ubus-at-client $(1)/usr/bin/
endef

$(eval $(call BuildPackage,ubus-at-client))