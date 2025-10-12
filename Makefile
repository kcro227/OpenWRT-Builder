# OpenWRT 项目构建系统
# 此 Makefile 提供项目管理和 OpenWRT 编译的统一接口

# 项目根目录
BASE_DIR := $(shell pwd)

# 默认目标
.DEFAULT_GOAL := all

# 编译线程数
BUILD_JOBS := 16

# 获取所有可用的目标型号
TARGETS := $(notdir $(wildcard configs/*))

# 检查是否通过命令行指定了目标型号
ifneq ($(filter target=%,$(MAKECMDGOALS)),)
    SELECTED_TARGET := $(patsubst target=%,%,$(filter target=%,$(MAKECMDGOALS)))
else
    # 尝试从保存的文件中读取目标型号
    ifneq ($(wildcard .selected_target),)
        SELECTED_TARGET := $(shell cat .selected_target)
    else
        SELECTED_TARGET :=
    endif
endif

# 源码目录
SRC_DIR := $(BASE_DIR)/srcs/$(SELECTED_TARGET)

# 工具路径
SCRIPT_DIR := $(BASE_DIR)/scripts
CUSTOMIZE_TOOL := $(SCRIPT_DIR)/customize/customize
FEEDS_TOOL := $(SCRIPT_DIR)/feeds/feeds
PM_INSTALL_TOOL := $(SCRIPT_DIR)/pm-install/pm-install
INIT_TARGET_TOOL := $(SCRIPT_DIR)/init-target/init-target
MENU_TOOL := $(SCRIPT_DIR)/menu/menu
BACKUP_TOOL := $(SCRIPT_DIR)/backup/backup
COPY_TOOL := $(SCRIPT_DIR)/copy/copy

# 获取作者名称
ifneq ($(SELECTED_TARGET),)
    ifeq ($(wildcard configs/$(SELECTED_TARGET)/customize.config),)
        AUTHOR_NAME := unknown
    else
        AUTHOR_NAME := $(shell grep "^AUTHOR=" configs/$(SELECTED_TARGET)/customize.config | cut -d= -f2 | tr -d '"' || echo "unknown")
    endif
else
    AUTHOR_NAME := unknown
endif

# 伪目标声明
.PHONY: all script init update install build copy clean distclean menu help config \
        build-clean download first-time wrt-% check-target update-code feeds full-build

# 默认完整构建流程
all:build

full-build:script check-target update-code init feeds config build

# 编译所有工具脚本
script:
	@echo "编译工具脚本..."
	@$(MAKE) -C $(SCRIPT_DIR)/utils
	@$(MAKE) -C $(SCRIPT_DIR)/feeds
	@$(MAKE) -C $(SCRIPT_DIR)/customize
	@$(MAKE) -C $(SCRIPT_DIR)/init-target
	@$(MAKE) -C $(SCRIPT_DIR)/pm-install
	@$(MAKE) -C $(SCRIPT_DIR)/menu
	@$(MAKE) -C $(SCRIPT_DIR)/backup
	@$(MAKE) -C $(SCRIPT_DIR)/copy
	@echo "工具脚本编译完成"

script-clean:
	@echo "清理工具脚本..."
	@$(MAKE) -C $(SCRIPT_DIR)/utils clean
	@$(MAKE) -C $(SCRIPT_DIR)/feeds clean
	@$(MAKE) -C $(SCRIPT_DIR)/customize clean
	@$(MAKE) -C $(SCRIPT_DIR)/init-target clean
	@$(MAKE) -C $(SCRIPT_DIR)/pm-install clean
	@$(MAKE) -C $(SCRIPT_DIR)/menu clean
	@$(MAKE) -C $(SCRIPT_DIR)/backup clean
	@$(MAKE) -C $(SCRIPT_DIR)/copy clean
	@echo "工具脚本清理完成"
	
# 初始化目标：下载源码、安装feeds、应用自定义配置和安装软件包
init: check-target
	@echo "备份文件"
	@$(BACKUP_TOOL) $(SELECTED_TARGET) backup
	@echo "初始化目标: $(SELECTED_TARGET)"
	@$(CUSTOMIZE_TOOL) configs/$(SELECTED_TARGET)/customize.config -c init -s $(SRC_DIR)
	@$(PM_INSTALL_TOOL) -i $(SELECTED_TARGET) $(AUTHOR_NAME)
	@echo "目标初始化完成"

# 更新源码
update-code:
	@$(INIT_TARGET_TOOL) $(SELECTED_TARGET) -u

# 更新feeds包
feeds:
	@echo "更新feeds软件包"
	@$(SRC_DIR)/scripts/feeds update -a
	@echo "安装feeds软件包"
	@$(SRC_DIR)/scripts/feeds install -a

# 更新自定义软件包
update: check-target
	@echo "更新目标: $(SELECTED_TARGET)"
	@$(FEEDS_TOOL) update
	@echo "更新完成"

# 安装软件包到源码中
install: check-target
	@echo "安装软件包到目标: $(SELECTED_TARGET)"
	@$(PM_INSTALL_TOOL) -i $(SELECTED_TARGET) $(AUTHOR_NAME)
	@echo "软件包安装完成"

# 编译目标
build: check-target
	@echo "编译目标: $(SELECTED_TARGET)"
	@$(CUSTOMIZE_TOOL) configs/$(SELECTED_TARGET)/customize.config -c build -s $(SRC_DIR)
	@make -C srcs/$(SELECTED_TARGET) -j$(BUILD_JOBS) V=s
	@echo "编译完成"

# 复制编译产物到指定路径
# 支持 make copy (默认操作) 和 make copy ID=1 (指定序号)
# 支持 make copy -m "release" (添加标记)
copy: check-target script
	@echo "复制编译产物..."
	$(eval COPY_ARGS := )
	$(if $(ID),$(eval COPY_ARGS := $(COPY_ARGS) -r $(ID)))
	$(if $(M),$(eval COPY_ARGS := $(COPY_ARGS) -m $(M)))
	@if [ -n "$(ID)" ] || [ -n "$(M)" ]; then \
		echo "执行指定规则: $(if $(ID),ID=$(ID))$(if $(M), M=$(M))"; \
		$(COPY_TOOL) -c configs/$(SELECTED_TARGET)/copy.conf $(COPY_ARGS); \
	else \
		echo "执行默认规则"; \
		$(COPY_TOOL) -c configs/$(SELECTED_TARGET)/copy.conf; \
	fi
	@echo "复制完成"

# 打开配置菜单
config:
	@echo "打开配置菜单"
	@make -C srcs/$(SELECTED_TARGET) menuconfig

# 清理操作
clean:
	@$(BACKUP_TOOL) $(SELECTED_TARGET) clean

# 清理编译文件
clean-build: check-target
	@echo "清理目标: $(SELECTED_TARGET)"
	@make -C $(SRC_DIR) clean
	@echo "清理完成"

# 彻底清理（包括下载的文件）
distclean: check-target
	@echo "彻底清理目标: $(SELECTED_TARGET)"
	@make -C srcs/$(SELECTED_TARGET) distclean
	@echo "彻底清理完成"

# 下载源码
download:
	@$(MAKE) -C srcs/$(SELECTED_TARGET) download -j$(nproc) V=s

# 首次构建完整流程
first-time: script check-target update-code init feeds config download build

# 交互式菜单
menu:
	@$(MENU_TOOL) $(TARGETS)
	@if [ -f .selected_target ]; then \
		echo "已选择目标: $$(cat .selected_target)"; \
	fi

# 检查是否已选择目标
check-target:
ifneq ($(SELECTED_TARGET),)
	@true
else
	@echo "未选择目标型号，显示交互菜单..."
	@$(MENU_TOOL) $(TARGETS)
	@if [ -f .selected_target ]; then \
		SELECTED_TARGET=$$(cat .selected_target); \
		echo "已选择目标: $$SELECTED_TARGET"; \
		$(MAKE) target=$$SELECTED_TARGET $(MAKECMDGOALS); \
	else \
		echo "错误: 需要指定目标型号"; \
		echo "可用型号: $(TARGETS)"; \
		echo "请使用 'make target=<型号> <操作>' 或运行 'make menu' 选择目标"; \
		exit 1; \
	fi
endif

# OpenWRT 源码中的 make 命令传递
wrt-%: check-target
	@echo "在目标 $(SELECTED_TARGET) 上执行: make $*"
	@make -C $(SRC_DIR) $*

# 显示帮助信息
help:
	@echo "OpenWRT 项目构建系统"
	@echo ""
	@echo "用法: make [target=<型号>] <操作>"
	@echo ""
	@echo "可用操作:"
	@echo "  all         完整构建流程（编译脚本、初始化、编译）"
	@echo "  script      编译所有工具脚本"
	@echo "  init        初始化目标（下载源码、安装feeds、应用配置、安装软件包）"
	@echo "  update      更新自定义软件包"
	@echo "  install     安装软件包"
	@echo "  build       编译目标"
	@echo "  copy        复制编译产物到指定路径"
	@echo "  copy ID=<n> 复制指定序号的编译产物"
	@echo "  copy M=<标记> 复制时添加标记目录"
	@echo "  config      打开menuconfig界面"
	@echo "  feeds       更新feeds软件包"
	@echo "  build-clean 清理编译文件"
	@echo "  distclean   彻底清理（包括下载的文件）"
	@echo "  menu        显示交互式菜单选择目标"
	@echo "  download    下载源码"
	@echo "  first-time  首次构建完整流程"
	@echo "  help        显示此帮助信息"
	@echo "  wrt-<cmd>   在OpenWRT源码中执行make命令，如wrt-menuconfig"
	@echo ""
	@echo "可用型号: $(TARGETS)"
	@echo ""
	@echo "示例:"
	@echo "  make target=m28c all      # 为 m28c 执行完整构建"
	@echo "  make menu                 # 显示菜单选择目标"
	@echo "  make target=xr30 build    # 编译 xr30 目标"
	@echo "  make wrt-menuconfig       # 在已选择的目标上执行menuconfig"
	@echo "  make copy                 # 执行默认复制操作"
	@echo "  make copy ID=1            # 执行序号1的复制规则"
	@echo "  make copy ID=1,2,3        # 执行序号1,2,3的复制规则"
	@echo "  make copy ID=all          # 执行所有复制规则"
	@echo "  make copy M=release       # 复制时添加release标记目录"
	@echo "  make copy ID=1 M=release  # 执行序号1的复制规则并添加release标记目录"