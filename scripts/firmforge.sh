#!/bin/bash

# =============================================
# OpenWrt高级构建管理系统
# 版本: 3.8.1
# 作者: KCrO
# 更新: 2025-07-09
# 优化: 增强日志系统和进度显示
# =============================================

# 全局常量
AUTHOR="KCrO"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}/.."
RES_DIR="${PROJECT_ROOT}/resources"
SRC_DIR="${PROJECT_ROOT}/src"
PKG_CONFIG="${SCRIPT_DIR}/packages.config"
DL_CONFIG="${SCRIPT_DIR}/download.config"
BACKUP_DIR="${RES_DIR}/backups"
COPY_CONFIG="${SCRIPT_DIR}/copy.config"
CUSTOMIZE_CONFIG="${SCRIPT_DIR}/customize.config"
DEFCONFIG_DIR="${RES_DIR}/defconfig"  # 保存defconfig的目录

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
LOG_LEVEL=${LOG_LEVEL:-"INFO"}

# 初始化日志系统
init_logging() {
    LOG_DIR="${RES_DIR}/logs"
    mkdir -p "$LOG_DIR"
    find "$LOG_DIR" -name 'build-*.log' -mtime +7 -exec rm -f {} \;
    
    local log_file="${LOG_DIR}/build-$(date +%Y.%m.%d-%H:%M:%S).log"
    exec 3>&1 4>&2
    
    if [[ $1 != "config" ]]; then
        exec > >(tee -a "$log_file") 2>&1
    fi
}

# 增强日志函数
log() {
    local level=$1
    local message=$2
    local timestamp=$(date +"%T")
    local caller_info=""
    
    declare -A log_levels=([DEBUG]=0 [INFO]=1 [SUCCESS]=2 [WARNING]=3 [ERROR]=4)
    [[ ${log_levels[$level]} -lt ${log_levels[$LOG_LEVEL]} ]] && return
    
    local icon color
    case $level in
        "DEBUG")   icon="🛠️ "  ; color="${MAGENTA}" ;;
        "INFO")    icon="ℹ️ "  ; color="${BLUE}" ;;
        "SUCCESS") icon="✅ "  ; color="${GREEN}" ;;
        "WARNING") icon="⚠️ "  ; color="${YELLOW}" ;;
        "ERROR")   icon="❌ "  ; color="${RED}" ;;
        *)         icon="🔹 "  ; color="${NC}" ;;
    esac
    
    # DEBUG级别添加调用信息
    if [[ "$level" == "DEBUG" ]]; then
        local func_name="${FUNCNAME[1]}"
        local line_no="${BASH_LINENO[0]}"
        caller_info="[${func_name}:${line_no}] "
    fi
    
    local level_padded=$(printf "%-7s" "[$level]")
    # 添加文件/操作信息（如果可用）
    local context=""
    [[ -n "$3" ]] && context="(${3}) "
    
    echo -e "[${timestamp}] ${BOLD}${color}${level_padded}${NC} ${icon} ${caller_info}${context}${message}" >&3
}

# 修改后的进度条显示函数
show_progress_bar() {
    local current=$1
    local total=$2
    local msg=$3
    local width=50  # 进度条宽度
    
    # 计算百分比
    local percent=$((current * 100 / total))
    # 计算完成的方块数量
    local completed_chars=$((current * width / total))
    local remaining_chars=$((width - completed_chars))

    # 构建进度条字符串
    local bar="${GREEN}"
    for ((i=0; i<completed_chars; i++)); do
        bar+="▓"
    done
    bar+="${YELLOW}"
    for ((i=0; i<remaining_chars; i++)); do
        bar+="░"
    done
    bar+="${NC}"

    # 构建进度信息
    local progress_info="[${bar}] ${percent}% (${current}/${total}) ${msg}"
    
    # 输出进度条 - 总是清除整行
    echo -ne "\033[2K\r${progress_info}"
    
    # 完成后换行
    if [ $current -ge $total ]; then
        echo ""
    fi
}

# 增强错误处理
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

# 关键文件备份
backup_critical_files() {
    log INFO "开始备份关键文件"
    log DEBUG "备份目录: $BACKUP_DIR" "文件备份"
    mkdir -p "$BACKUP_DIR"
    
    local backup_targets=("$FEEDS_CONF" "$ZZZ_SETTINGS")
    local backup_count=0
    
    for target in "${backup_targets[@]}"; do
        [ -f "$target" ] || {
            log WARNING "跳过不存在的文件: ${target/#$PROJECT_ROOT\//}" "文件备份"
            continue
        }
        
        local bak_file="${BACKUP_DIR}/$(basename "$target").$(date +%Y%m%d-%H%M%S).bak"
        if cp -v "$target" "$bak_file"; then
            log SUCCESS "备份成功: ${bak_file/#$PROJECT_ROOT\//}" "文件备份"
            ((backup_count++))
        else
            log ERROR "备份失败: ${target/#$PROJECT_ROOT\//}" "文件备份"
            return 1
        fi
    done
    
    if [ $backup_count -gt 0 ]; then
        log SUCCESS "关键文件备份完成 (共备份 ${backup_count} 个文件)" "文件备份"
    else
        log WARNING "没有需要备份的文件" "文件备份"
    fi
}

# 安装自定义软件包
install_custom_packages() {
    log INFO "开始安装自定义软件包"
    local total=0 success=0
    local pids=()
    
    local config_lines=()
    while IFS= read -r line; do
        [[ $line =~ ^#|^$ ]] && continue
        config_lines+=("$line")
    done < "$PKG_CONFIG"
    
    total=${#config_lines[@]}
    [ $total -eq 0 ] && {
        log WARNING "没有找到需要安装的自定义软件包" "软件包安装"
        return 0
    }
    
    log INFO "发现 ${total} 个需要安装的软件包" "软件包安装"
    
    # 显示进度条
    (
        local last_reported=0
        while [ $success -lt $total ]; do
            sleep 0.5
            if [ $success -gt $last_reported ] || [ $success -eq $total ]; then
                show_progress_bar $success $total "安装软件包"
                last_reported=$success
            fi
        done
    ) &
    local progress_pid=$!
    
    for line in "${config_lines[@]}"; do
        (
            pkg_name=$(echo "$line" | awk '{print $1}')
            dest_base=$(echo "$line" | awk '{print $2}')
            [ -z "$pkg_name" ] || [ -z "$dest_base" ] && {
                log ERROR "无效配置行: $line" "软件包安装"
                exit 1
            }
            
            pkg_basename=$(basename "$pkg_name")
            src_path="${PROJECT_ROOT}/packages/${pkg_name}"
            dest_path="${PROJECT_ROOT}/${dest_base}/package/${AUTHOR}/${pkg_basename}"
            
            log DEBUG "处理软件包: $pkg_name" "软件包安装"
            log DEBUG "源路径: $src_path" "软件包安装"
            log DEBUG "目标路径: $dest_path" "软件包安装"
            
            validate_dir "$src_path" || {
                log ERROR "软件包源目录不存在: ${src_path/#$PROJECT_ROOT\//}" "软件包安装"
                exit 1
            }
            
            mkdir -p "$(dirname "$dest_path")" || {
                log ERROR "创建目录失败: $(dirname "$dest_path")" "软件包安装"
                exit 1
            }
            
            if [ -d "$dest_path" ]; then
                log WARNING "已存在包: $pkg_basename, 正在覆盖..." "软件包安装"
                rm -rf "$dest_path" || {
                    log ERROR "删除失败: ${dest_path/#$PROJECT_ROOT\//}" "软件包安装"
                    exit 1
                }
            fi
            
            if cp -a "$src_path" "$dest_path"; then
                log SUCCESS "安装成功: $pkg_name → ${dest_path/#$PROJECT_ROOT\//}" "软件包安装"
            else
                log ERROR "安装失败: $pkg_basename" "软件包安装"
                exit 1
            fi
        ) &
        pids+=($!)
    done
    
    local completed=0
    for pid in "${pids[@]}"; do
        if wait $pid; then
            ((success++))
        else
            log WARNING "软件包安装任务失败" "软件包安装"
        fi
        ((completed++))
        show_progress_bar $completed $total "安装软件包"
    done
    
    # 结束进度条进程
    kill $progress_pid >/dev/null 2>&1
    wait $progress_pid 2>/dev/null
    
    if [ $success -eq $total ]; then
        log SUCCESS "软件包安装完成 (${success}/${total} 全部成功)" "软件包安装"
    else
        log ERROR "软件包安装完成 (成功: ${success}/${total}, 失败: $((total-success)))" "软件包安装"
        return 1
    fi
}

# 清理构建环境
clean_build_environment() {
    confirm_action "您确定要清理构建环境吗? 这将删除所有自定义包并恢复配置文件" || {
        log INFO "清理操作已取消" "环境清理"
        return
    }
    
    log INFO "开始清理构建环境" "环境清理"
    local deleted_dirs=0 restored_files=0
    
    while IFS= read -r line; do
        clean_line=$(echo "$line" | sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        [ -z "$clean_line" ] && continue
        
        dest_base=$(echo "$clean_line" | awk '{print $2}')
        custom_pkg_dir="${PROJECT_ROOT}/${dest_base}/package/${AUTHOR}"
        
        [ -d "$custom_pkg_dir" ] && {
            if rm -rf "$custom_pkg_dir"; then
                log SUCCESS "已删除: ${custom_pkg_dir/#$PROJECT_ROOT\//}" "环境清理"
                ((deleted_dirs++))
            else
                log ERROR "删除失败: ${custom_pkg_dir/#$PROJECT_ROOT\//}" "环境清理"
            fi
        }
    done < "$PKG_CONFIG"
    
    local restore_files=("$FEEDS_CONF" "$ZZZ_SETTINGS")
    for file in "${restore_files[@]}"; do
        local latest_bak=$(ls -t "${BACKUP_DIR}/$(basename "$file")".*.bak 2>/dev/null | head -1)
        [ -n "$latest_bak" ] && {
            if cp -f "$latest_bak" "$file"; then
                log SUCCESS "已恢复: ${file/#$PROJECT_ROOT\//}" "环境清理"
                ((restored_files++))
            else
                log ERROR "恢复失败: ${file/#$PROJECT_ROOT\//}" "环境清理"
            fi
        }
    done
    
    log SUCCESS "构建环境清理完成" "环境清理"
    log INFO "已删除 ${deleted_dirs} 个目录, 恢复 ${restored_files} 个文件" "环境清理"
}

# 应用定制规则
apply_customization() {
    local target_file=$(eval echo "$1")
    local action="$2"
    local arg1="$3"
    local arg2="$4"
    
    log DEBUG "应用定制规则: $action 到 $target_file" "配置定制"
    log DEBUG "参数1: '$arg1'" "配置定制"
    log DEBUG "参数2: '$arg2'" "配置定制"
    
    validate_file "$target_file" || {
        [[ "$action" == "append" ]] && {
            touch "$target_file" || {
                log ERROR "创建文件失败: ${target_file/#$PROJECT_ROOT\//}" "配置定制"
                return 1
            }
            log WARNING "创建文件: ${target_file/#$PROJECT_ROOT\//}" "配置定制"
        } || {
            log WARNING "目标文件不存在: ${target_file/#$PROJECT_ROOT\//}" "配置定制"
            return 1
        }
    }
    
    case "$action" in
        "replace")
            [ -z "$arg1" ] || [ -z "$arg2" ] && {
                log WARNING "替换操作需要两个参数: 查找字符串和替换字符串" "配置定制"
                return 1
            }
            sed -i "s|${arg1}|${arg2}|g" "$target_file" || {
                log ERROR "替换失败: ${target_file/#$PROJECT_ROOT\//}" "配置定制"
                return 1
            }
            ;;
            
        "insert-after"|"insert-before")
            [ -z "$arg1" ] || [ -z "$arg2" ] && {
                log WARNING "插入操作需要两个参数: 匹配字符串和插入内容" "配置定制"
                return 1
            }
            
            grep -qF "$arg2" "$target_file" && {
                log WARNING "跳过重复插入: 目标文件中已存在相同内容" "配置定制"
                return 0
            }
            
            local sed_cmd
            [[ "$action" == "insert-after" ]] && sed_cmd="a" || sed_cmd="i"
            
            sed -i "/${arg1}/${sed_cmd} \\${arg2}" "$target_file" || {
                log ERROR "插入失败: ${target_file/#$PROJECT_ROOT\//}" "配置定制"
                return 1
            }
            ;;
            
        "append")
            [ -z "$arg1" ] && {
                log WARNING "追加操作需要内容参数" "配置定制"
                return 1
            }
            
            grep -qF "$arg1" "$target_file" && {
                log WARNING "跳过重复追加: 目标文件中已存在相同内容" "配置定制"
                return 0
            }
            
            echo -e "$arg1" >> "$target_file" || {
                log ERROR "追加失败: ${target_file/#$PROJECT_ROOT\//}" "配置定制"
                return 1
            }
            ;;
            
        "delete")
            [ -z "$arg1" ] && {
                log WARNING "删除操作需要匹配字符串" "配置定制"
                return 1
            }
            
            sed -i "/${arg1}/d" "$target_file" || {
                log ERROR "删除失败: ${target_file/#$PROJECT_ROOT\//}" "配置定制"
                return 1
            }
            ;;
            
        *)
            log WARNING "未知操作类型: $action" "配置定制"
            return 1
            ;;
    esac
    
    log SUCCESS "操作成功: $action → ${target_file/#$PROJECT_ROOT\//}" "配置定制"
    return 0
}

# 定制配置文件
customize_config_files() {
    local context="$1"
    local build_time="$2"
    
    log INFO "开始${context}阶段配置文件定制" "配置定制"
    local applied_rules=0
    
    if [ ! -f "$CUSTOMIZE_CONFIG" ]; then
        log WARNING "定制配置文件不存在，使用默认设置" "配置定制"
        if [ "$context" == "init" ]; then
            customize_default_settings_init
        elif [ "$context" == "build" ]; then
            customize_default_settings_build "$build_time"
        fi
        return 0
    fi
    
    local line_count=0
    while IFS= read -r line; do
        [[ $line =~ ^# || -z $line ]] && continue
        ((line_count++))
        
        line=$(echo "$line" | sed -e "s|\${AUTHOR}|$AUTHOR|g" \
                                  -e "s|\${PROJECT_ROOT}|$PROJECT_ROOT|g" \
                                  -e "s|\${SRC_DIR}|$SRC_DIR|g" \
                                  -e "s|\${ZZZ_SETTINGS}|$ZZZ_SETTINGS|g")
        
        IFS=';' read -r line_context action target_file arg1 arg2 <<< "$line"
        [ "$line_context" != "$context" ] && [ "$line_context" != "all" ] && continue
        
        [ -n "$build_time" ] && arg2=$(echo "$arg2" | sed "s/__BUILD_TIME__/$build_time/g")
        
        apply_customization "$target_file" "$action" "$arg1" "$arg2" && ((applied_rules++))
        
    done < "$CUSTOMIZE_CONFIG"
    
    if [ $line_count -eq 0 ]; then
        log WARNING "没有找到适用于${context}上下文的定制规则" "配置定制"
        if [ "$context" == "init" ]; then
            customize_default_settings_init
        elif [ "$context" == "build" ]; then
            customize_default_settings_build "$build_time"
        fi
    else
        log SUCCESS "${context}阶段配置文件定制完成 (应用 ${applied_rules}/${line_count} 条规则)" "配置定制"
    fi
}

# 初始化阶段默认设置定制
customize_default_settings_init() {
    log INFO "应用初始化阶段默认设置" "配置定制"
    local applied=0
    
    # 1. 修改固件描述信息
    local target_desc="LEDE Build by ${AUTHOR} @ __BUILD_TIME__"
    if apply_customization "$ZZZ_SETTINGS" "replace" "DISTRIB_DESCRIPTION='.*'" "DISTRIB_DESCRIPTION='${target_desc}'"; then
        ((applied++))
    fi
    
    # 2. 添加网络和主机名配置
    local network_config="uci set network.lan.ipaddr='192.168.8.1'   # 默认 IP 地址"
    local hostname_config="uci set system.@system[0].hostname='M28C'"
    
    if ! grep -qF "$network_config" "$ZZZ_SETTINGS"; then
        apply_customization "$ZZZ_SETTINGS" "insert-after" "DISTRIB_DESCRIPTION='LEDE Build by ${AUTHOR} @ __BUILD_TIME__'" "$network_config" && ((applied++))
    fi
    
    if ! grep -qF "$hostname_config" "$ZZZ_SETTINGS"; then
        apply_customization "$ZZZ_SETTINGS" "insert-after" "DISTRIB_DESCRIPTION='LEDE Build by ${AUTHOR} @ __BUILD_TIME__'" "$hostname_config" && ((applied++))
    fi
    
    log INFO "应用了 ${applied} 条默认设置" "配置定制"
}

# 编译阶段默认设置定制
customize_default_settings_build() {
    local build_time="$1"
    log INFO "应用编译阶段默认设置" "配置定制"
    local applied=0
    
    local target_desc="LEDE Build by ${AUTHOR} @ ${build_time}"
    sed -i "s|DISTRIB_DESCRIPTION='.*'|DISTRIB_DESCRIPTION='${target_desc}'|g" "$ZZZ_SETTINGS" && {
        log SUCCESS "构建时间更新成功: ${ZZZ_SETTINGS/#$PROJECT_ROOT\//}" "配置定制"
        ((applied++))
    }
    
    log INFO "应用了 ${applied} 条默认设置" "配置定制"
}

# 初始化构建环境
initialize_build_environment() {
    log INFO "开始初始化构建环境" "环境初始化"
    local start_time=$(date +%s)
    
    backup_critical_files || {
        log ERROR "关键文件备份失败，初始化中止" "环境初始化"
        return 1
    }
    
    install_custom_packages || {
        log ERROR "软件包安装失败，初始化中止" "环境初始化"
        return 1
    }
    
    customize_config_files "init"
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    log SUCCESS "构建环境初始化完成 (耗时: ${duration}秒)" "环境初始化"
}

# 下载单个软件包
download_single_package() {
    local line="$1"
    local type name repo_info dest_path
    type=$(echo "$line" | awk '{print $1}')
    name=$(echo "$line" | awk '{print $2}')
    repo_info=$(echo "$line" | awk '{print $3}')
    dest_path=$(echo "$line" | awk '{$1=$2=$3=""; print $0}' | sed -e 's/^[[:space:]]*//')
    
    local repo branch
    repo="${repo_info%;*}"
    branch="${repo_info#*;}"
    branch="${branch:-master}"
    
    local target_dir="${PROJECT_ROOT}/${dest_path}"
    [ -d "$target_dir" ] && {
        log WARNING "已存在包: $name, 跳过下载" "软件包下载"
        return 0
    }
    
    mkdir -p "$(dirname "$target_dir")" || {
        log ERROR "创建目录失败: $(dirname "$target_dir")" "软件包下载"
        return 1
    }
    
    log DEBUG "开始下载包: $name" "软件包下载"
    log DEBUG "类型: $type, 仓库: $repo, 分支: $branch" "软件包下载"
    log DEBUG "目标目录: $target_dir" "软件包下载"
    
    for attempt in {1..3}; do
        log INFO "下载尝试 (${attempt}/3): $name" "软件包下载"
        
        local clone_cmd="git clone --depth 1 --quiet"
        [ -n "$branch" ] && [ "$branch" != "$repo" ] && clone_cmd+=" -b $branch"
        
        log DEBUG "执行命令: $clone_cmd $repo $target_dir" "软件包下载"
        $clone_cmd "$repo" "$target_dir" 2>/dev/null && {
            log SUCCESS "下载成功: $name → ${target_dir/#$PROJECT_ROOT\//}" "软件包下载"
            return 0
        }
        
        log WARNING "下载失败 (尝试: ${attempt}/3)" "软件包下载"
        sleep $((attempt * 2))
        rm -rf "$target_dir"
        
        [ $attempt -eq 3 ] && [ -z "$branch" ] && {
            log INFO "尝试默认分支" "软件包下载"
            git clone --depth 1 --quiet "$repo" "$target_dir" 2>/dev/null && {
                log SUCCESS "下载成功（默认分支）: $name" "软件包下载"
                return 0
            }
        }
    done
    
    log ERROR "下载失败: $name" "软件包下载"
    return 1
}

# 下载远程软件包
download_remote_packages() {
    log INFO "开始下载远程软件包" "软件包下载"
    local start_time=$(date +%s)
    local total=0 success=0
    local pids=()
    
    local config_lines=()
    while IFS= read -r line; do
        [[ $line =~ ^#|^$ ]] && continue
        config_lines+=("$line")
    done < "$DL_CONFIG"
    
    total=${#config_lines[@]}
    [ $total -eq 0 ] && {
        log WARNING "没有找到需要下载的软件包" "软件包下载"
        return 0
    }
    
    log INFO "发现 ${total} 个需要下载的软件包" "软件包下载"
    
    # 显示进度条
    (
        local last_reported=0
        while [ $success -lt $total ]; do
            sleep 0.5
            if [ $success -gt $last_reported ] || [ $success -eq $total ]; then
                show_progress_bar $success $total "下载软件包"
                last_reported=$success
            fi
        done
    ) &
    local progress_pid=$!
    
    for line in "${config_lines[@]}"; do
        (
            download_single_package "$line" || exit 1
        ) &
        pids+=($!)
    done
    
    local completed=0
    for pid in "${pids[@]}"; do
        if wait $pid; then
            ((success++))
        else
            log WARNING "软件包下载任务失败" "软件包下载"
        fi
        ((completed++))
        show_progress_bar $completed $total "下载软件包"
    done
    
    # 结束进度条进程
    kill $progress_pid >/dev/null 2>&1
    wait $progress_pid 2>/dev/null
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    if [ $success -eq $total ]; then
        log SUCCESS "软件包下载完成 (${success}/${total} 全部成功, 耗时: ${duration}秒)" "软件包下载"
    else
        log ERROR "软件包下载完成 (成功: ${success}/${total}, 失败: $((total-success)), 耗时: ${duration}秒)" "软件包下载"
        return 1
    fi
}

# 更新单个软件包
update_single_package() {
    local line="$1"
    local type name repo_info dest_path
    type=$(echo "$line" | awk '{print $1}')
    name=$(echo "$line" | awk '{print $2}')
    repo_info=$(echo "$line" | awk '{print $3}')
    dest_path=$(echo "$line" | awk '{$1=$2=$3=""; print $0}' | sed -e 's/^[[:space:]]*//')
    
    local repo branch
    repo="${repo_info%;*}"
    branch="${repo_info#*;}"
    branch="${branch:-master}"
    
    local target_dir="${PROJECT_ROOT}/${dest_path}"
    [ ! -d "$target_dir" ] && {
        log INFO "包不存在: $name, 开始下载..." "软件包更新"
        download_single_package "$line" && return 0
        return 1
    }
    
    [ ! -d "$target_dir/.git" ] && {
        log WARNING "非git仓库: ${target_dir/#$PROJECT_ROOT\//}" "软件包更新"
        return 0
    }
    
    pushd "$target_dir" >/dev/null || {
        log ERROR "无法进入目录: ${target_dir/#$PROJECT_ROOT\//}" "软件包更新"
        return 1
    }
    
    log DEBUG "开始更新包: $name" "软件包更新"
    log DEBUG "类型: $type, 仓库: $repo, 分支: $branch" "软件包更新"
    log DEBUG "目标目录: $target_dir" "软件包更新"
    
    local current_commit=$(git rev-parse --short HEAD 2>/dev/null)
    [ -z "$current_commit" ] && current_commit="unknown"
    
    local update_output
    update_output=$(git fetch --all 2>&1 && git reset --hard "origin/$branch" 2>&1)
    local update_result=$?
    
    local new_commit=$(git rev-parse --short HEAD 2>/dev/null)
    [ -z "$new_commit" ] && new_commit="unknown"
    
    if [ $update_result -eq 0 ]; then
        if [ "$current_commit" != "$new_commit" ]; then
            log SUCCESS "更新成功: $name (${current_commit} → ${new_commit})" "软件包更新"
            log DEBUG "更新输出: $update_output" "软件包更新"
        else
            log INFO "已是最新: $name (${current_commit})" "软件包更新"
        fi
    else
        log ERROR "更新失败: $name" "软件包更新"
        log DEBUG "错误详情: $update_output" "软件包更新"
    fi
    
    popd >/dev/null
    return $update_result
}

# 修改后的软件包更新函数
update_downloaded_packages() {
    local packages_to_update=("$@")
    log INFO "开始更新已下载软件包" "软件包更新"
    local start_time=$(date +%s)
    local total=0 success=0
    
    local config_lines=()
    while IFS= read -r line; do
        [[ $line =~ ^# || -z $line ]] && continue
        
        if [ ${#packages_to_update[@]} -gt 0 ]; then
            local pkg_name=$(echo "$line" | awk '{print $2}')
            printf '%s\n' "${packages_to_update[@]}" | grep -q "^$pkg_name$" || continue
        fi
        
        config_lines+=("$line")
    done < "$DL_CONFIG"
    
    total=${#config_lines[@]}
    if [ $total -eq 0 ]; then
        if [ ${#packages_to_update[@]} -gt 0 ]; then
            log WARNING "未找到指定的包: ${packages_to_update[*]}" "软件包更新"
        else
            log WARNING "没有需要更新的软件包" "软件包更新"
        fi
        return 0
    fi
    
    local package_names=()
    for line in "${config_lines[@]}"; do
        package_names+=("$(echo "$line" | awk '{print $2}')")
    done
    log INFO "发现 ${total} 个需要更新的软件包: ${package_names[*]}" "软件包更新"
    
    local index=0
    for line in "${config_lines[@]}"; do
        # 获取包名用于状态显示
        local pkg_name=$(echo "$line" | awk '{print $2}')
        
        # 更新包并捕获状态信息
        local status_msg=""
        if update_single_package "$line"; then
            ((success++))
            # 获取当前提交ID
            local repo_info=$(echo "$line" | awk '{print $3}')
            local dest_path=$(echo "$line" | awk '{$1=$2=$3=""; print $0}' | sed -e 's/^[[:space:]]*//')
            local target_dir="${PROJECT_ROOT}/${dest_path}"
            
            if [ -d "${target_dir}/.git" ]; then
                pushd "${target_dir}" >/dev/null
                local commit_hash=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
                popd >/dev/null
                status_msg="(软件包更新) 已是最新: ${pkg_name} (${commit_hash})"
            else
                status_msg="(软件包更新) 已是最新: ${pkg_name}"
            fi
        else
            status_msg="(软件包更新) 更新失败: ${pkg_name}"
        fi
        
        ((index++))
        show_progress_bar $index $total "$status_msg"
    done
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    if [ $success -eq $total ]; then
        log SUCCESS "软件包更新完成 (${success}/${total} 全部成功, 耗时: ${duration}秒)" "软件包更新"
    else
        log ERROR "软件包更新完成 (成功: ${success}/${total}, 失败: $((total-success)), 耗时: ${duration}秒)" "软件包更新"
        return 1
    fi
}

# 更新并安装feeds
update_and_install_feeds() {
    log INFO "开始更新feeds包" "feeds管理"
    validate_dir "$SRC_DIR" || return 1
    
    pushd "$SRC_DIR" >/dev/null || return 1
    
    local progress_pid=$!
    
    log DEBUG "执行: ./scripts/feeds update -a" "feeds管理"
    ./scripts/feeds update -a || {
        kill $progress_pid >/dev/null 2>&1
        popd >/dev/null
        log ERROR "更新feeds失败" "feeds管理"
        return 1
    }
    
    kill $progress_pid >/dev/null 2>&1
    wait $progress_pid 2>/dev/null
    echo -ne "\r\033[K"
    
    log INFO "开始安装feeds包" "feeds管理"
    
    progress_pid=$!
    
    log DEBUG "执行: ./scripts/feeds install -a" "feeds管理"
    ./scripts/feeds install -a || {
        kill $progress_pid >/dev/null 2>&1
        log ERROR "安装feeds失败" "feeds管理"
        return 1
    }
    
    kill $progress_pid >/dev/null 2>&1
    wait $progress_pid 2>/dev/null
    echo -ne "\r\033[K"
    
    popd >/dev/null
    log SUCCESS "feeds安装完成" "feeds管理"
}

# 编译固件
compile_firmware() {
    log INFO "开始编译固件" "固件编译"
    validate_dir "$SRC_DIR" || return 1
    
    local jobs=${BUILD_JOBS:-$(nproc)}
    local start_time=$(date +%s)
    local build_time=$(date +"%Y.%m.%d-%H:%M")
    
    customize_config_files "build" "$build_time"
    
    pushd "$SRC_DIR" >/dev/null || return 1
    
    # 显示编译进度
    (
        local start_ts=$(date +%s)
        while true; do
            local current_ts=$(date +%s)
            local elapsed=$((current_ts - start_ts))
            local elapsed_str=$(printf "%02d:%02d:%02d" $((elapsed/3600)) $(((elapsed%3600)/60)) $((elapsed%60)))
        done
    ) &
    local progress_pid=$!
    
    log DEBUG "执行: make -j$jobs V=s" "固件编译"
    make -j"$jobs" V=s
    local result=$?
    
    kill $progress_pid >/dev/null 2>&1
    wait $progress_pid 2>/dev/null
    echo -ne "\r\033[K"
    
    popd >/dev/null
    
    local end_time=$(date +%s)
    local compile_seconds=$((end_time - start_time))
    local compile_time=$(printf "%02d:%02d:%02d" $((compile_seconds/3600)) $(((compile_seconds%3600)/60)) $((compile_seconds%60)))
    
    if [ $result -eq 0 ]; then
        log SUCCESS "固件编译成功! 耗时: $compile_time" "固件编译"
    else
        log ERROR "固件编译失败! 耗时: $compile_time" "固件编译"
        log ERROR "建议: 检查编译日志获取详细错误信息" "固件编译"
    fi
    return $result
}

# 清理编译文件
clean_compilation_files() {
    confirm_action "您确定要清理编译文件吗? 这将删除所有编译生成的文件" || {
        log INFO "清理操作已取消" "环境清理"
        return
    }
    
    log INFO "开始清理编译文件" "环境清理"
    validate_dir "$SRC_DIR" || return 1
    
    pushd "$SRC_DIR" >/dev/null || return 1
    log DEBUG "执行: make clean" "环境清理"
    make clean || {
        log ERROR "清理编译文件时出错" "环境清理"
        return 1
    }
    popd >/dev/null
    log SUCCESS "编译文件清理完成" "环境清理"
}

# 运行交互式配置
run_interactive_configuration() {
    log INFO "启动交互式配置菜单" "配置管理"
    validate_dir "$SRC_DIR" || return 1
    
    exec >/dev/tty 2>&1
    pushd "$SRC_DIR" >/dev/null || return 1
    log DEBUG "执行: make menuconfig" "配置管理"
    make menuconfig
    local result=$?
    popd >/dev/null
    
    [ $result -eq 0 ] && log SUCCESS "配置菜单操作完成" "配置管理" || log ERROR "配置菜单操作失败" "配置管理"
    return $result
}

# 复制构建产物
copy_build_artifacts() {
    log INFO "开始复制构建产物" "构建产物"
    local total_files=0 copied_files=0 config_found=0
    local start_time=$(date +%s)
    
    validate_file "$COPY_CONFIG" || {
        log ERROR "复制配置文件不存在: ${COPY_CONFIG/#$PROJECT_ROOT\//}" "构建产物"
        return 1
    }
    
    local current_date=$(date +%Y-%m-%d)
    
    # 显示进度条
    local current=0
    (
        while [ $copied_files -lt $total_files ]; do
            sleep 0.5
            show_progress_bar $copied_files $total_files "复制构建产物"
        done
    ) &
    local progress_pid=$!
    
    while IFS= read -r line; do
        [[ $line =~ ^# || -z $line ]] && continue
        ((config_found++))
        
        read -r src_pattern dest_base <<< "$line"
        [ -z "$src_pattern" ] || [ -z "$dest_base" ] && {
            log WARNING "跳过无效配置行: $line" "构建产物"
            continue
        }
        
        local target_dir="${dest_base}/${current_date}"
        mkdir -p "$target_dir" || {
            log ERROR "创建目录失败: $target_dir" "构建产物"
            continue
        }
        
        local full_src_path="${SRC_DIR}/${src_pattern}"
        shopt -s nullglob
        local expanded_files=($full_src_path)
        shopt -u nullglob
        
        [ ${#expanded_files[@]} -eq 0 ] && {
            log WARNING "没有找到匹配的文件: $src_pattern" "构建产物"
            continue
        }
        
        total_files=$((total_files + ${#expanded_files[@]}))
        
        local found_files=0
        for file in "${expanded_files[@]}"; do
            [ -e "$file" ] || continue
            local relative_path="${file/#$SRC_DIR\//}"
            cp -v "$file" "$target_dir/" && {
                log SUCCESS "复制: $relative_path → ${target_dir/#$PROJECT_ROOT\//}" "构建产物"
                ((found_files++))
                ((copied_files++))
                ((current++))
            }
        done
        
        [ $found_files -gt 0 ] && log INFO "已复制 $found_files 个文件到: ${target_dir/#$PROJECT_ROOT\//}" "构建产物"
    done < "$COPY_CONFIG"
    
    # 结束进度条进程
    kill $progress_pid >/dev/null 2>&1
    wait $progress_pid 2>/dev/null
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    [ $config_found -eq 0 ] && log WARNING "配置文件中没有有效的配置行" "构建产物"
    
    if [ $copied_files -gt 0 ]; then
        log SUCCESS "构建产物复制完成 (总计: $copied_files/$total_files, 耗时: ${duration}秒)" "构建产物"
    else
        log WARNING "没有复制任何文件 (耗时: ${duration}秒)" "构建产物"
    fi
    [ $copied_files -gt 0 ] || return 1
}

# 完整构建流程
full_build_process() {
    log INFO "启动完整构建流程" "完整构建"
    local start_time=$(date +%s)
    
    update_downloaded_packages || log WARNING "更新软件包失败，继续构建" "完整构建"
    install_custom_packages || log WARNING "安装软件包失败，继续构建" "完整构建"
    customize_config_files "init"
    update_and_install_feeds || log WARNING "更新feeds失败，继续构建" "完整构建"
    compile_firmware || return 1
    copy_build_artifacts || log WARNING "构建产物复制失败，但构建已完成" "完整构建"
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    log SUCCESS "完整构建流程成功完成! (总耗时: ${duration}秒)" "完整构建"
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

# 主函数
main() {
    trap 'trap_error ${LINENO} "$BASH_COMMAND"' ERR
    init_logging "$1"
    
    case "$1" in
    init) initialize_build_environment ;;
    clean) clean_build_environment ;;
    backup) backup_critical_files ;;
    install) install_custom_packages ;;
    download) download_remote_packages ;;
    update) shift; update_downloaded_packages "$@" ;;
    feeds) update_and_install_feeds ;;
    build) compile_firmware ;;
    clean-build) clean_compilation_files ;;
    config) run_interactive_configuration ;;
    copy) copy_build_artifacts ;;
    full-build) full_build_process ;;
    help | *) show_help ;;
    esac
    
    exit 0
}

# 启动脚本
main "$@"