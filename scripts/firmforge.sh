#!/bin/bash

# =============================================
# OpenWrt高级构建管理系统
# 版本: 3.1
# 作者: KCrO
# 更新: 2025-07-02
# =============================================

# 全局常量
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}/.."
RES_DIR="${PROJECT_ROOT}/resources"
SRC_DIR="${PROJECT_ROOT}/src"
PKG_CONFIG="${SCRIPT_DIR}/packages.config"
DL_CONFIG="${SCRIPT_DIR}/download.config"
BACKUP_DIR="${RES_DIR}/backups"

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

# 日志级别 (DEBUG, INFO, WARNING, ERROR)
LOG_LEVEL=${LOG_LEVEL:-"DEBUG"}

source ~/.bashrc

# 初始化日志系统
init_logging() {
    LOG_DIR="${RES_DIR}/logs"
    mkdir -p "$LOG_DIR"

    # 日志轮转 (保留最近7个日志)
    find "$LOG_DIR" -name 'build-*.log' -mtime +7 -exec rm -f {} \;

    local log_file="${LOG_DIR}/build-$(date +%Y.%m.%d-%H:%M:%S).log"
    exec 3>&1 4>&2

    # 对非交互命令才重定向日志
    if [[ $1 != "config" ]]; then
        exec > >(tee -a "$log_file") 2>&1
    fi
}

# 日志函数
log() {
    local level=$1
    local message=$2
    local timestamp=$(date +"%T.%3N")

    # 日志级别过滤
    declare -A log_levels=([DEBUG]=0 [INFO]=1 [WARNING]=2 [ERROR]=3)
    [[ ${log_levels[$level]} -lt ${log_levels[$LOG_LEVEL]} ]] && return

    # 日志颜色
    local color
    case $level in
    "DEBUG") color="${MAGENTA}" ;;
    "INFO") color="${BLUE}" ;;
    "SUCCESS") color="${GREEN}" ;;
    "WARNING") color="${YELLOW}" ;;
    "ERROR") color="${RED}" ;;
    *) color="${NC}" ;;
    esac

    # 日志格式
    local log_msg="[${timestamp}] ${BOLD}${color}${level}${NC}: ${message}"
    echo -e "$log_msg" >&3
}

# 错误处理
trap_error() {
    local lineno=$1
    local msg=$2
    log ERROR "脚本异常退出! 行号: $lineno, 错误: $msg"
    exit 1
}

# 目录验证
validate_dir() {
    [ -d "$1" ] || {
        log ERROR "目录不存在: ${1/#$PROJECT_ROOT\//}"
        return 1
    }
}

# 文件验证
validate_file() {
    [ -f "$1" ] || {
        log ERROR "文件不存在: ${1/#$PROJECT_ROOT\//}"
        return 1
    }
}

# 用户确认
confirm_action() {
    local msg=$1
    echo -en "${YELLOW}${msg} (y/N) ${NC}"
    read -r response
    [[ $response =~ ^[Yy]$ ]] || return 1
    return 0
}

# 进度指示器
show_progress() {
    local pid=$1
    local msg=$2
    local delay=0.2
    local spin_chars=('⣾' '⣽' '⣻' '⢿' '⡿' '⣟' '⣯' '⣷')

    while kill -0 "$pid" 2>/dev/null; do
        for char in "${spin_chars[@]}"; do
            echo -ne "\r${BLUE}${char}${NC} ${msg}"
            sleep $delay
        done
    done
    echo -ne "\r${GREEN}✓${NC} ${msg}完成"
    echo
}

# 版本化备份
backup_critical_files() {
    log INFO "开始系统备份"
    mkdir -p "$BACKUP_DIR"

    local backup_targets=(
        "$FEEDS_CONF"
        "$ZZZ_SETTINGS"
    )

    for target in "${backup_targets[@]}"; do
        [ -f "$target" ] || {
            log WARNING "跳过不存在的文件: ${target/#$PROJECT_ROOT\//}"
            continue
        }

        local bak_file="${BACKUP_DIR}/$(basename "$target").$(date +%Y%m%d-%H%M%S).bak"
        if cp -v "$target" "$bak_file"; then
            log SUCCESS "备份成功: ${bak_file/#$PROJECT_ROOT\//}"
        else
            log ERROR "备份失败: ${target/#$PROJECT_ROOT\//}"
            return 1
        fi
    done
}

# 安装软件包
install_packages() {
    log INFO "开始安装软件包"
    local total=0 success=0
    local pids=()

    # 预读配置
    local config_lines=()
    while IFS= read -r line; do
        config_lines+=("$line")
    done < <(grep -v '^#' "$PKG_CONFIG" | grep -v '^$')

    total=${#config_lines[@]}
    log DEBUG "找到 $total 个需要安装的包"

    # 并行处理
    for line in "${config_lines[@]}"; do
        (
            # 解析字段
            pkg_name=$(echo "$line" | awk '{print $1}')
            dest_base=$(echo "$line" | awk '{print $2}')

            # 验证字段
            if [[ -z "$pkg_name" || -z "$dest_base" ]]; then
                log ERROR "无效配置行: $line"
                exit 1
            fi

            # 获取包名的最后一部分
            pkg_basename=$(basename "$pkg_name")

            src_path="${PROJECT_ROOT}/packages/${pkg_name}"
            dest_path="${PROJECT_ROOT}/${dest_base}/package/own/${pkg_basename}"

            # 验证源目录
            validate_dir "$src_path" || exit 1

            # 创建目标目录
            mkdir -p "$(dirname "$dest_path")" || {
                log ERROR "创建目录失败: $(dirname "$dest_path")"
                exit 1
            }

            # 检查目标是否存在
            if [ -d "$dest_path" ]; then
                log WARNING "已存在包: $pkg_basename, 正在覆盖..."
                rm -rf "$dest_path" || {
                    log ERROR "删除失败: ${dest_path/#$PROJECT_ROOT\//}"
                    exit 1
                }
            fi

            # 执行复制
            if cp -a "$src_path" "$dest_path"; then
                log SUCCESS "安装成功: $pkg_name → ${dest_path/#$PROJECT_ROOT\//}"
            else
                log ERROR "安装失败: $pkg_basename"
                exit 1
            fi
        ) &
        pids+=($!)
    done

    # 等待所有进程完成
    for pid in "${pids[@]}"; do
        if wait "$pid"; then
            ((success++))
        fi
    done

    log INFO "安装完成 (成功: ${success}/${total})"
    [ "$success" -eq "$total" ] || return 1
}

# 清理工程
clean_project() {
    log WARNING "即将执行清理操作，这将删除所有自定义包并恢复配置文件"
    confirm_action "您确定要继续吗?" || {
        log INFO "清理操作已取消"
        return
    }

    log INFO "开始清理工程"

    # 删除所有package/own目录
    while IFS= read -r line; do
        clean_line=$(echo "$line" | sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        [ -z "$clean_line" ] && continue

        dest_base=$(echo "$clean_line" | awk '{print $2}')
        own_dir="${PROJECT_ROOT}/${dest_base}/package/own"

        [ -d "$own_dir" ] && {
            if rm -rf "$own_dir"; then
                log SUCCESS "已删除: ${own_dir/#$PROJECT_ROOT\//}"
            else
                log ERROR "删除失败: ${own_dir/#$PROJECT_ROOT\//}"
            fi
        }
    done <"$PKG_CONFIG"

    # 恢复备份文件
    local restore_files=(
        "$FEEDS_CONF"
        "$ZZZ_SETTINGS"
    )

    for file in "${restore_files[@]}"; do
        local latest_bak=$(ls -t "${BACKUP_DIR}/$(basename "$file")".*.bak 2>/dev/null | head -1)
        [ -n "$latest_bak" ] && {
            if cp -f "$latest_bak" "$file"; then
                log SUCCESS "已恢复: ${file/#$PROJECT_ROOT\//}"
            else
                log ERROR "恢复失败: ${file/#$PROJECT_ROOT\//}"
            fi
        }
    done

    log SUCCESS "清理操作完成"
}

# 初始化工程
initialize_project() {
    log INFO "开始初始化流程"

    # 1. 备份关键文件
    backup_critical_files || {
        log ERROR "关键文件备份失败，初始化中止"
        return 1
    }

    # 2. 安装软件包
    install_packages || {
        log ERROR "软件包安装失败，初始化中止"
        return 1
    }

    # 3. 修改zzz-default-settings文件
    log INFO "开始修改zzz-default-settings文件"
    validate_file "$ZZZ_SETTINGS" || {
        log ERROR "无法找到zzz-default-settings文件"
        return 1
    }

    # 修改固件描述信息（不包含构建时间）
    if sed -i "s|DISTRIB_DESCRIPTION='LEDE[^']*'|DISTRIB_DESCRIPTION='LEDE Build by KCrO '|g" "$ZZZ_SETTINGS"; then
        log SUCCESS "固件描述修改成功"
    else
        log ERROR "固件描述修改失败"
        return 1
    fi

    # 添加网络和主机名配置 - 直接在描述信息修改后添加
    local network_config="uci set network.lan.ipaddr='192.168.8.1'   # 默认 IP 地址"
    local hostname_config="uci set system.@system[0].hostname='M28C'"

    # 删除可能存在的旧配置
    sed -i "\|$network_config|d" "$ZZZ_SETTINGS"
    sed -i "\|$hostname_config|d" "$ZZZ_SETTINGS"

    # 在描述信息行后添加新配置
    if sed -i "/DISTRIB_DESCRIPTION='LEDE Build by KCrO '/a \\
    $network_config \\
    $hostname_config" "$ZZZ_SETTINGS"; then
        log SUCCESS "添加网络和主机名配置"
    else
        log ERROR "添加网络和主机名配置失败"
        return 1
    fi

    log SUCCESS "工程初始化完成"
}

# 下载软件包
download_packages() {
    log INFO "开始下载软件包"
    local total=0 success=0
    local pids=()

    # 预读配置
    local config_lines=()
    while IFS= read -r line; do
        config_lines+=("$line")
    done < <(grep -v '^#' "$DL_CONFIG" | grep -v '^$')

    total=${#config_lines[@]}
    log DEBUG "找到 $total 个需要下载的包"

    for line in "${config_lines[@]}"; do
        (
            # 解析字段（类型 名称 仓库URL;分支 目标路径）
            type=$(echo "$line" | awk '{print $1}')
            name=$(echo "$line" | awk '{print $2}')
            repo_info=$(echo "$line" | awk '{print $3}')
            dest_path=$(echo "$line" | awk '{$1=$2=$3=""; print $0}' | sed -e 's/^[[:space:]]*//')

            # 解析仓库和分支
            repo="${repo_info%;*}"
            branch="${repo_info#*;}"

            # 构建目标路径
            target_dir="${PROJECT_ROOT}/${dest_path}"

            # 跳过已存在的包
            if [ -d "$target_dir" ]; then
                log WARNING "跳过已存在包: $name"
                exit 0
            fi

            # 创建父目录
            mkdir -p "$(dirname "$target_dir")" || {
                log ERROR "创建目录失败: $(dirname "$target_dir")"
                exit 1
            }

            # 带重试的下载
            for attempt in {1..3}; do
                log INFO "下载尝试 (${attempt}/3): $name"

                # 动态构建clone命令
                clone_cmd="git clone --depth 1 --quiet"
                if [[ -n "$branch" && "$branch" != "$repo" ]]; then
                    clone_cmd+=" -b $branch"
                fi

                if $clone_cmd "$repo" "$target_dir" 2>/dev/null; then
                    log SUCCESS "下载成功: $name → ${target_dir/#$PROJECT_ROOT\//}"
                    echo "success" >&1
                    exit 0
                else
                    log WARNING "下载失败 (尝试: ${attempt}/3)"
                    sleep $((attempt * 2)) # 递增等待时间
                    rm -rf "$target_dir"

                    # 最后一次尝试使用默认分支
                    if [[ $attempt -eq 3 && -z "$branch" ]]; then
                        log INFO "尝试默认分支"
                        if git clone --depth 1 --quiet "$repo" "$target_dir" 2>/dev/null; then
                            log SUCCESS "下载成功（默认分支）: $name"
                            echo "success" >&1
                            exit 0
                        fi
                    fi
                fi
            done

            log ERROR "下载失败: $name"
            exit 1
        ) &
        pids+=($!)
    done

    # 显示进度
    for pid in "${pids[@]}"; do
        show_progress $pid "下载软件包" &
        wait $pid && ((success++))
    done

    log INFO "下载完成 (成功: ${success}/${total})"
    [ "$success" -eq "$total" ] || return 1
}

# 更新软件包
update_packages() {
    log INFO "开始更新软件包"
    local total=0 success=0
    local pids=()

    # 预读配置
    local config_lines=()
    while IFS= read -r line; do
        config_lines+=("$line")
    done < <(grep -v '^#' "$DL_CONFIG" | grep -v '^$')

    total=${#config_lines[@]}
    log DEBUG "找到 $total 个需要更新的包"

    for line in "${config_lines[@]}"; do
        (
            # 设置子shell的错误处理
            set -e
            
            # 解析字段
            type=$(echo "$line" | awk '{print $1}')
            name=$(echo "$line" | awk '{print $2}')
            repo_info=$(echo "$line" | awk '{print $3}')
            dest_path=$(echo "$line" | awk '{$1=$2=$3=""; print $0}' | sed -e 's/^[[:space:]]*//')
            
            # 分割仓库和分支
            IFS=';' read -r repo branch <<<"$repo_info"
            branch="${branch:-master}" # 默认master分支
            
            # 构建目标路径
            target_dir="${PROJECT_ROOT}/${dest_path}"
            
            # 检查目录有效性
            if [ ! -d "$target_dir" ]; then
                log WARNING "跳过未安装包: $name"
                exit 0  # 正常退出，不算失败
            fi
            
            if [ ! -d "$target_dir/.git" ]; then
                log WARNING "非git仓库: ${target_dir/#$PROJECT_ROOT\//}"
                exit 0  # 正常退出，不算失败
            fi
            
            # 进入目录
            if ! pushd "$target_dir" >/dev/null; then
                log ERROR "无法进入目录: ${target_dir/#$PROJECT_ROOT\//}"
                exit 1
            fi
            
            # 分支处理
            current_branch=$(git symbolic-ref --short HEAD 2>/dev/null)
            if [[ "$current_branch" != "$branch" ]]; then
                log INFO "切换分支: $current_branch -> $branch"
                if ! git checkout -q "$branch"; then
                    log ERROR "分支切换失败: $name → $branch"
                    exit 1
                fi
            fi
            
            # 带重试的更新
            local update_success=0
            for attempt in {1..3}; do
                log INFO "更新尝试 (${attempt}/3): $name"
                if git fetch --all --quiet && git reset --hard "origin/$branch" --quiet; then
                    log SUCCESS "更新成功: $name"
                    update_success=1
                    break
                else
                    log WARNING "更新失败 (尝试: ${attempt}/3)"
                    sleep $((attempt * 2))
                    
                    # 最后一次尝试强制清理
                    if [ $attempt -eq 3 ]; then
                        git reset --hard HEAD
                        git clean -df
                        if git pull --quiet; then
                            log SUCCESS "强制更新成功: $name"
                            update_success=1
                            break
                        fi
                    fi
                fi
            done
            
            # 退出目录
            popd >/dev/null
            
            # 根据更新结果退出
            if [ $update_success -eq 1 ]; then
                exit 0  # 成功退出
            else
                log ERROR "更新失败: $name"
                exit 1  # 失败退出
            fi
        ) &
        pids+=($!)
    done
    
    # 等待所有后台进程完成并计数
    for pid in "${pids[@]}"; do
        if wait "$pid"; then
            ((success++))
        fi
    done
    
    log INFO "更新完成 (成功: ${success}/${total})"
    [ "$success" -eq "$total" ] || return 1
}

# 更新并安装feeds
update_feeds() {
    log INFO "开始更新feeds包"
    validate_dir "$SRC_DIR" || return 1

    pushd "$SRC_DIR" >/dev/null || return 1

    # 更新feeds
    if ./scripts/feeds update -a; then
        log SUCCESS "feeds更新成功"
    else
        popd >/dev/null
        log ERROR "更新feeds失败"
        return 1
    fi

    log INFO "开始安装feeds包"
    # 安装feeds
    if ./scripts/feeds install -a; then
        log SUCCESS "feeds安装完成"
    else
        log ERROR "安装feeds失败"
        return 1
    fi

    popd >/dev/null
}

# 编译固件
compile_firmware() {
    log INFO "开始编译固件"
    validate_dir "$SRC_DIR" || return 1

    # 设置线程数（默认使用所有核心）
    local jobs=${BUILD_JOBS:-$(nproc)}

    # 记录开始时间
    local start_time=$(date +%s)

    # 获取当前时间作为构建时间
    local build_time=$(date +"%Y.%m.%d-%H:%M")

    # 更新固件描述信息（添加构建时间）
    log INFO "更新固件描述信息"
    validate_file "$ZZZ_SETTINGS" || {
        log ERROR "无法找到zzz-default-settings文件"
        return 1
    }

    # 更新固件描述信息
    if sed -i "s|DISTRIB_DESCRIPTION='LEDE Build by KCrO[^']*'|DISTRIB_DESCRIPTION='LEDE Build by KCrO @ ${build_time} '|g" "$ZZZ_SETTINGS"; then
        log SUCCESS "固件描述更新成功 (构建时间: ${build_time})"
    else
        log ERROR "固件描述更新失败"
        return 1
    fi

    pushd "$SRC_DIR" >/dev/null || return 1

    # 显示编译进度
    make -j"$jobs" V=s
    local result=$?
    popd >/dev/null || return 1

    # 计算编译耗时
    local end_time=$(date +%s)
    local compile_seconds=$((end_time - start_time))
    local compile_time=$(printf "%02d:%02d:%02d" \
        $((compile_seconds / 3600)) \
        $(((compile_seconds % 3600) / 60)) \
        $((compile_seconds % 60)))

    if [ $result -eq 0 ]; then
        log SUCCESS "固件编译成功! 耗时: $compile_time"
    else
        log ERROR "固件编译失败! 耗时: $compile_time"
    fi
}

# 清理编译文件
clean_compilation() {
    log WARNING "即将清理编译文件，这将删除所有编译生成的文件"
    confirm_action "您确定要继续吗?" || {
        log INFO "清理操作已取消"
        return
    }

    log INFO "开始清理编译文件"
    validate_dir "$SRC_DIR" || return 1

    pushd "$SRC_DIR" >/dev/null || return 1
    if make clean; then
        log SUCCESS "编译文件清理完成"
    else
        log ERROR "清理编译文件时出错"
        return 1
    fi
    popd >/dev/null || return 1
}

# 运行交互配置
run_interactive_config() {
    log INFO "启动交互式配置菜单"
    validate_dir "$SRC_DIR" || return 1

    # 临时关闭日志重定向
    exec >/dev/tty 2>&1

    pushd "$SRC_DIR" >/dev/null || return 1
    make menuconfig
    local result=$?
    popd >/dev/null || return 1

    # 重新启用日志重定向
    exec > >(tee -a "$LOG_FILE") 2>&1

    if [ $result -eq 0 ]; then
        log SUCCESS "配置菜单操作完成"
    else
        log ERROR "配置菜单操作失败"
        return 1
    fi
}

# 显示帮助信息
show_help() {
    echo -e "${GREEN}${BOLD}OpenWrt高级构建管理系统 v3.1${NC}"
    echo -e "${CYAN}=============================================${NC}"
    echo
    echo -e "${BOLD}使用方法: $0 [命令]${NC}"
    echo
    echo -e "${YELLOW}${BOLD}工程管理命令:${NC}"
    echo "  init            完整初始化 (备份→安装→覆盖)"
    echo "  clean           清理工程 (删除包+恢复配置)"
    echo "  backup          备份原始配置文件"
    echo
    echo -e "${YELLOW}${BOLD}包管理命令:${NC}"
    echo "  install         安装软件包"
    echo "  download        下载远程软件包"
    echo "  update          更新已下载的软件包"
    echo "  feeds           更新并安装feeds"
    echo
    echo -e "${YELLOW}${BOLD}编译命令:${NC}"
    echo "  build           编译固件"
    echo "  clean-build     清理编译产生的文件"
    echo "  config          启动交互式配置菜单"
    echo
    echo -e "${YELLOW}${BOLD}高级命令:${NC}"
    echo "  full-build      完整构建流程 (下载→安装→更新→编译)"
    echo "  help            显示帮助信息"
    echo
    echo -e "${YELLOW}${BOLD}环境变量:${NC}"
    echo "  BUILD_JOBS      设置编译线程数 (默认: CPU核心数)"
    echo "                  示例: BUILD_JOBS=4 $0 build"
    echo "  LOG_LEVEL       设置日志级别 (DEBUG, INFO, WARNING, ERROR)"
    echo "                  示例: LOG_LEVEL=DEBUG $0 build"
    echo
    echo -e "${YELLOW}${BOLD}配置文件:${NC}"
    echo -e "  包配置文件:   ${UNDERLINE}${PKG_CONFIG/#$PROJECT_ROOT\//}${NC}"
    echo -e "  下载配置:     ${UNDERLINE}${DL_CONFIG/#$PROJECT_ROOT\//}${NC}"
    echo -e "  资源目录:     ${UNDERLINE}${RES_DIR/#$PROJECT_ROOT\//}${NC}"
    echo
    echo -e "${CYAN}=============================================${NC}"
}

# 完整构建流程
full_build() {
    log INFO "启动完整构建流程"

    download_packages || {
        log ERROR "下载软件包失败，构建中止"
        return 1
    }

    install_packages || {
        log ERROR "安装软件包失败，构建中止"
        return 1
    }

    update_feeds || {
        log ERROR "更新feeds失败，构建中止"
        return 1
    }

    compile_firmware || {
        log ERROR "固件编译失败"
        return 1
    }

    log SUCCESS "完整构建流程成功完成!"
}

# 主函数
main() {
    # 设置错误陷阱
    trap 'trap_error ${LINENO} "$BASH_COMMAND"' ERR

    # 初始化日志
    init_logging "$1"

    case "$1" in
    init) initialize_project ;;
    clean) clean_project ;;
    backup) backup_critical_files ;;
    install) install_packages ;;
    download) download_packages ;;
    update) update_packages ;;
    feeds) update_feeds ;;
    build) compile_firmware ;;
    clean-build) clean_compilation ;;
    config) run_interactive_config ;;
    full-build) full_build ;;
    help | *) show_help ;;
    esac

    exit 0
}

main "$@"
