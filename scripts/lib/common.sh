#!/bin/bash
# 公共函数和常量库

# 全局常量
AUTHOR="KCrO"
PROJECT_ROOT="${SCRIPT_DIR}/.."
RES_DIR="${PROJECT_ROOT}/resources"
SRC_DIR="${PROJECT_ROOT}/src"
PKG_CONFIG="${SCRIPT_DIR}/config/packages.config"
DL_CONFIG="${SCRIPT_DIR}/config/download.config"
BACKUP_DIR="${RES_DIR}/backups"
COPY_CONFIG="${SCRIPT_DIR}/config/copy.config"
CUSTOMIZE_CONFIG="${SCRIPT_DIR}/config/customize.config"
DEFCONFIG_DIR="${RES_DIR}/defconfig"

# 固定文件路径
FEEDS_CONF="${SRC_DIR}/feeds.conf.default"
ZZZ_SETTINGS="${SRC_DIR}/package/lean/default-settings/files/zzz-default-settings"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'
UNDERLINE='\033[4m'

# 目录验证函数
validate_dir() {
    [ -d "$1" ] || {
        log ERROR "目录不存在: ${1/#$PROJECT_ROOT\//}" "目录验证"
        log INFO "建议: 检查路径是否正确或运行 'init' 命令初始化环境" "目录验证"
        return 1
    }
}

# 文件验证函数
validate_file() {
    [ -f "$1" ] || {
        log ERROR "文件不存在: ${1/#$PROJECT_ROOT\//}" "文件验证"
        log INFO "建议: 检查文件路径或确认配置文件已创建" "文件验证"
        return 1
    }
}

# 用户确认函数
confirm_action() {
    local msg=$1
    echo -en "${YELLOW}${BOLD}${msg} (y/N) ${NC}"
    read -r response
    [[ $response =~ ^[Yy]$ ]] || return 1
    return 0
}

# 替换变量函数
replace_vars() {
    local input="$1"
    local build_time="$2"
    
    # 替换时间占位符
    input=${input//__BUILD_TIME__/$build_time}
    
    # 替换全局常量
    input=${input//\$\{AUTHOR\}/$AUTHOR}
    input=${input//\$\{SCRIPT_DIR\}/$SCRIPT_DIR}
    input=${input//\$\{PROJECT_ROOT\}/$PROJECT_ROOT}
    input=${input//\$\{RES_DIR\}/$RES_DIR}
    input=${input//\$\{SRC_DIR\}/$SRC_DIR}
    input=${input//\$\{PKG_CONFIG\}/$PKG_CONFIG}
    input=${input//\$\{DL_CONFIG\}/$DL_CONFIG}
    input=${input//\$\{BACKUP_DIR\}/$BACKUP_DIR}
    input=${input//\$\{COPY_CONFIG\}/$COPY_CONFIG}
    input=${input//\$\{CUSTOMIZE_CONFIG\}/$CUSTOMIZE_CONFIG}
    input=${input//\$\{DEFCONFIG_DIR\}/$DEFCONFIG_DIR}
    input=${input//\$\{FEEDS_CONF\}/$FEEDS_CONF}
    input=${input//\$\{ZZZ_SETTINGS\}/$ZZZ_SETTINGS}
    
    echo "$input"
}

# 错误处理函数
trap_error() {
    local lineno=$1
    local msg=$2
    log ERROR "脚本异常退出! 行号: $lineno, 错误: $msg" "错误处理"
    log ERROR "建议: 检查脚本参数或系统资源，查看日志获取详细信息" "错误处理"
    
    # DEBUG级别添加调用栈
    if [[ "$LOG_LEVEL" == "DEBUG" ]]; then
        log DEBUG "调用栈信息:" "错误处理"
        local frame=0
        while caller $frame; do
            ((frame++))
        done | while read line func file; do
            log DEBUG "  $file:$line 函数 $func" "错误处理"
        done
    fi
    
    exit 1
}

# 显示帮助信息
show_help() {
    echo -e "${GREEN}${BOLD}OpenWrt高级构建管理系统 v3.8.1${NC}"
    echo -e "${CYAN}=============================================${NC}"
    echo
    echo -e "${BOLD}使用方法: $0 [命令] [选项]${NC}"
    echo
    echo -e "${YELLOW}${BOLD}环境管理命令:${NC}"
    echo "  init            初始化构建环境 (备份→安装→配置)"
    echo "  clean           清理构建环境 (删除包+恢复配置)"
    echo "  backup          备份原始配置文件"
    echo
    echo -e "${YELLOW}${BOLD}包管理命令:${NC}"
    echo "  install         安装自定义软件包"
    echo "  download        下载远程软件包"
    echo "  update [包名...] 更新所有或指定的软件包"
    echo "  feeds           更新并安装feeds"
    echo
    echo -e "${YELLOW}${BOLD}构建命令:${NC}"
    echo "  build           编译固件"
    echo "  clean-build     清理编译产生的文件"
    echo "  config          启动交互式配置菜单"
    echo "  copy            复制构建产物到目标目录"
    echo
    echo -e "${YELLOW}${BOLD}高级命令:${NC}"
    echo "  full-build      完整构建流程 (下载→安装→更新→编译)"
    echo "  help            显示帮助信息"
    echo
    echo -e "${YELLOW}${BOLD}环境变量:${NC}"
    echo "  BUILD_JOBS      设置编译线程数 (默认: CPU核心数)"
    echo "  LOG_LEVEL       设置日志级别 (DEBUG, INFO, WARNING, ERROR)"
    echo
    echo -e "${YELLOW}${BOLD}配置文件:${NC}"
    echo -e "  包配置文件:   ${UNDERLINE}${PKG_CONFIG/#$PROJECT_ROOT\//}${NC}"
    echo -e "  下载配置:     ${UNDERLINE}${DL_CONFIG/#$PROJECT_ROOT\//}${NC}"
    echo -e "  复制配置:     ${UNDERLINE}${COPY_CONFIG/#$PROJECT_ROOT\//}${NC}"
    echo -e "  定制配置:     ${UNDERLINE}${CUSTOMIZE_CONFIG/#$PROJECT_ROOT\//}${NC}"
    echo
    echo -e "${CYAN}=============================================${NC}"
    echo
    echo -e "${BOLD}更新指定包示例:${NC}"
    echo "  $0 update package1 package2"
    echo
    echo -e "${BOLD}日志系统说明:${NC}"
    echo "  - 所有日志包含时间戳和操作上下文"
    echo "  - DEBUG级别日志显示调用函数和行号"
    echo "  - 进度条显示百分比和完成数量"
    echo "  - 错误日志包含详细错误信息和修复建议"
    echo
    echo -e "${BOLD}日志级别说明:${NC}"
    echo "  DEBUG   : 显示详细调试信息 (🛠️)"
    echo "  INFO    : 一般操作信息 (ℹ️)"
    echo "  SUCCESS : 操作成功信息 (✅)"
    echo "  WARNING : 警告信息 (⚠️)"
    echo "  ERROR   : 错误信息 (❌)"
    echo
    echo -e "${CYAN}=============================================${NC}"
}