include $(TOPDIR)/rules.mk

PKG_NAME:=fancontrol
PKG_VERSION:=1
PKG_RELEASE:=0

PKG_LICENSE:=MIT
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=KCrO <2209352301@qq.com>

PKG_BUILD_PARALLEL:=1

include $(INCLUDE_DIR)/package.mk

define Package/fancontrol
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=FanControl for OpenWRT
  DEPENDS:=+libubus +libubox +libjson-c
endef

define Package/fancontrol/description
  FanControl for OpenWRT using AT commands to get temperature data.
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) ./src/* $(PKG_BUILD_DIR)/
endef

TARGET_CFLAGS += \
	-I$(STAGING_DIR)/usr/include \
	-I$(STAGING_DIR)/usr/include/libubox \
	-I$(STAGING_DIR)/usr/include/libubus

TARGET_LDFLAGS += \
	-L$(STAGING_DIR)/usr/lib \
	-lubus -lubox -ljson-c

define Build/Compile
	$(TARGET_CC) $(TARGET_CFLAGS) -o $(PKG_BUILD_DIR)/fancontrol \
		$(PKG_BUILD_DIR)/*.c $(PKG_BUILD_DIR)/modules/*.c \
		$(TARGET_LDFLAGS)
endef

define Package/fancontrol/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/fancontrol $(1)/usr/bin/fancontrol
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/fancontrol.config $(1)/etc/config/fancontrol
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/fancontrol.init $(1)/etc/init.d/fancontrol
endef

$(eval $(call BuildPackage,fancontrol))