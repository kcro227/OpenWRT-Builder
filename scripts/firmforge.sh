#!/bin/bash

# =============================================
# OpenWrt高级构建管理系统
# 版本: 3.7
# 作者: KCrO
# 更新: 2025-07-04
# =============================================

# 全局常量
AUTHOR="KCrO"  # 作者信息，用于路径和固件描述
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"  # 脚本所在目录
PROJECT_ROOT="${SCRIPT_DIR}/.."  # 项目根目录
RES_DIR="${PROJECT_ROOT}/resources"  # 资源目录
SRC_DIR="${PROJECT_ROOT}/src"  # 源码目录
PKG_CONFIG="${SCRIPT_DIR}/packages.config"  # 软件包安装配置文件
DL_CONFIG="${SCRIPT_DIR}/download.config"  # 软件包下载配置文件
BACKUP_DIR="${RES_DIR}/backups"  # 备份文件目录
COPY_CONFIG="${SCRIPT_DIR}/copy.config"  # 文件复制配置文件
CUSTOMIZE_CONFIG="${SCRIPT_DIR}/customize.config"  # 配置文件定制规则

# 固定文件路径
FEEDS_CONF="${SRC_DIR}/feeds.conf.default"  # feeds配置文件
ZZZ_SETTINGS="${SRC_DIR}/package/lean/default-settings/files/zzz-default-settings"  # 默认设置文件

# 颜色定义
RED='\033[0;31m'       # 红色
GREEN='\033[0;32m'     # 绿色
YELLOW='\033[0;33m'    # 黄色
BLUE='\033[0;34m'      # 蓝色
MAGENTA='\033[0;35m'   # 紫色
CYAN='\033[0;36m'      # 青色
NC='\033[0m'           # 重置颜色
BOLD='\033[1m'         # 粗体
UNDERLINE='\033[4m'    # 下划线

# 日志级别 (DEBUG, INFO, WARNING, ERROR)
LOG_LEVEL=${LOG_LEVEL:-"INFO"}

# 初始化日志系统
init_logging() {
    LOG_DIR="${RES_DIR}/logs"  # 日志目录
    mkdir -p "$LOG_DIR"  # 创建日志目录

    # 日志轮转 (保留最近7个日志)
    find "$LOG_DIR" -name 'build-*.log' -mtime +7 -exec rm -f {} \;

    local log_file="${LOG_DIR}/build-$(date +%Y.%m.%d-%H:%M:%S).log"  # 日志文件名
    exec 3>&1 4>&2  # 保存标准输出和错误输出

    # 对非交互命令才重定向日志
    if [[ $1 != "config" ]]; then
        exec > >(tee -a "$log_file") 2>&1  # 重定向所有输出到日志文件和终端
    fi
}

# 日志函数 - 优化后的版本
log() {
    local level=$1
    local message=$2
    local timestamp=$(date +"%T")  # 简化时间戳格式

    # 日志级别过滤
    declare -A log_levels=([DEBUG]=0 [INFO]=1 [SUCCESS]=2 [WARNING]=3 [ERROR]=4)
    [[ ${log_levels[$level]} -lt ${log_levels[$LOG_LEVEL]} ]] && return

    # 日志图标和颜色
    local icon color
    case $level in
        "DEBUG")   icon="🛠️ "  ; color="${MAGENTA}" ;;
        "INFO")    icon="ℹ️ "  ; color="${BLUE}" ;;
        "SUCCESS") icon="✅ "  ; color="${GREEN}" ;;
        "WARNING") icon="⚠️ "  ; color="${YELLOW}" ;;
        "ERROR")   icon="❌ "  ; color="${RED}" ;;
        *)         icon="🔹 "  ; color="${NC}" ;;
    esac

    # 统一日志格式 - 添加对齐
    local level_padded=$(printf "%-7s" "[$level]")
    
    # 日志格式
    local log_msg="[${timestamp}] ${BOLD}${color}${level_padded}${NC} ${icon} ${message}"
    echo -e "$log_msg" >&3
}

# 错误处理函数
trap_error() {
    local lineno=$1
    local msg=$2
    log ERROR "脚本异常退出! 行号: $lineno, 错误: $msg"
    log ERROR "建议: 检查脚本参数或系统资源，查看日志获取详细信息"
    exit 1
}

# 目录验证函数
validate_dir() {
    [ -d "$1" ] || {
        log ERROR "目录不存在: ${1/#$PROJECT_ROOT\//}"  # 显示相对路径
        log INFO "建议: 检查路径是否正确或运行 'init' 命令初始化环境"
        return 1
    }
}

# 文件验证函数
validate_file() {
    [ -f "$1" ] || {
        log ERROR "文件不存在: ${1/#$PROJECT_ROOT\//}"  # 显示相对路径
        log INFO "建议: 检查文件路径或确认配置文件已创建"
        return 1
    }
}

# 用户确认函数
confirm_action() {
    local msg=$1
    echo -en "${YELLOW}${BOLD}${msg} (y/N) ${NC}"  # 黄色粗体提示
    read -r response
    [[ $response =~ ^[Yy]$ ]] || return 1
    return 0
}

# 进度指示器 - 优化后的版本
show_progress() {
    local pid=$1
    local msg=$2
    local delay=0.2
    local spin_chars=('⣾' '⣽' '⣻' '⢿' '⡿' '⣟' '⣯' '⣷')  # 旋转动画字符

    # 如果是非交互终端则不显示动画
    if [ ! -t 1 ]; then
        echo -ne "${BLUE}⏳${NC} ${msg}..."
        wait "$pid"
        echo -e "\r${GREEN}✓${NC} ${msg}完成"
        return
    fi

    # 显示进度动画直到进程结束
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        local char="${spin_chars[$i]}"
        echo -ne "\r${BLUE}${char}${NC} ${msg}"
        sleep $delay
        i=$(( (i+1) % ${#spin_chars[@]} ))
    done
    echo -ne "\r${GREEN}✓${NC} ${msg}完成"
    echo
}

# 关键文件备份
backup_critical_files() {
    log INFO "开始备份关键文件"
    mkdir -p "$BACKUP_DIR"  # 确保备份目录存在

    # 需要备份的文件列表
    local backup_targets=(
        "$FEEDS_CONF"
        "$ZZZ_SETTINGS"
    )
    
    local backup_count=0

    for target in "${backup_targets[@]}"; do
        [ -f "$target" ] || {
            log WARNING "跳过不存在的文件: ${target/#$PROJECT_ROOT\//}"
            continue
        }

        # 创建带时间戳的备份文件名
        local bak_file="${BACKUP_DIR}/$(basename "$target").$(date +%Y%m%d-%H%M%S).bak"
        if cp -v "$target" "$bak_file"; then
            log SUCCESS "备份成功: ${bak_file/#$PROJECT_ROOT\//}"
            ((backup_count++))
        else
            log ERROR "备份失败: ${target/#$PROJECT_ROOT\//}"
            return 1
        fi
    done
    
    if [ $backup_count -gt 0 ]; then
        log SUCCESS "关键文件备份完成 (共备份 ${backup_count} 个文件)"
    else
        log WARNING "没有需要备份的文件"
    fi
}

# 安装自定义软件包
install_custom_packages() {
    log INFO "开始安装自定义软件包"
    local total=0 success=0
    local pids=()

    # 读取配置文件
    local config_lines=()
    while IFS= read -r line; do
        config_lines+=("$line")
    done < <(grep -v '^#' "$PKG_CONFIG" | grep -v '^$')

    total=${#config_lines[@]}
    
    if [ $total -eq 0 ]; then
        log WARNING "没有找到需要安装的自定义软件包"
        return 0
    fi
    
    log INFO "发现 ${total} 个需要安装的软件包"

    # 并行处理每个软件包
    for line in "${config_lines[@]}"; do
        (
            # 解析配置行
            pkg_name=$(echo "$line" | awk '{print $1}')
            dest_base=$(echo "$line" | awk '{print $2}')

            # 验证字段
            if [[ -z "$pkg_name" || -z "$dest_base" ]]; then
                log ERROR "无效配置行: $line"
                exit 1
            fi

            # 获取包名的最后一部分
            pkg_basename=$(basename "$pkg_name")

            # 构建源路径和目标路径
            src_path="${PROJECT_ROOT}/packages/${pkg_name}"
            dest_path="${PROJECT_ROOT}/${dest_base}/package/${AUTHOR}/${pkg_basename}"

            # 验证源目录
            validate_dir "$src_path" || {
                log ERROR "软件包源目录不存在: ${src_path/#$PROJECT_ROOT\//}"
                exit 1
            }

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
        pids+=($!)  # 保存后台进程ID
    done

    # 等待所有进程完成
    for pid in "${pids[@]}"; do
        show_progress $pid "安装软件包" &
        wait $pid && ((success++))
    done

    if [ $success -eq $total ]; then
        log SUCCESS "软件包安装完成 (${success}/${total} 全部成功)"
    else
        log ERROR "软件包安装完成 (成功: ${success}/${total}, 失败: $((total-success)))"
        log WARNING "建议: 检查失败的软件包路径和权限设置"
        return 1
    fi
}

# 清理构建环境
clean_build_environment() {
    log WARNING "即将执行清理操作，这将删除所有自定义包并恢复配置文件"
    confirm_action "您确定要继续吗?" || {
        log INFO "清理操作已取消"
        return
    }

    log INFO "开始清理构建环境"
    local deleted_dirs=0 restored_files=0

    # 删除所有自定义软件包目录
    while IFS= read -r line; do
        clean_line=$(echo "$line" | sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        [ -z "$clean_line" ] && continue

        dest_base=$(echo "$clean_line" | awk '{print $2}')
        custom_pkg_dir="${PROJECT_ROOT}/${dest_base}/package/${AUTHOR}"

        [ -d "$custom_pkg_dir" ] && {
            if rm -rf "$custom_pkg_dir"; then
                log SUCCESS "已删除: ${custom_pkg_dir/#$PROJECT_ROOT\//}"
                ((deleted_dirs++))
            else
                log ERROR "删除失败: ${custom_pkg_dir/#$PROJECT_ROOT\//}"
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
                ((restored_files++))
            else
                log ERROR "恢复失败: ${file/#$PROJECT_ROOT\//}"
            fi
        }
    done

    log SUCCESS "构建环境清理完成"
    log INFO "已删除 ${deleted_dirs} 个目录, 恢复 ${restored_files} 个文件"
}

# 应用定制规则
apply_customization() {
    # 使用实际变量值替换路径中的占位符
    local target_file=$(eval echo "$1")
    local action="$2"
    local arg1="$3"
    local arg2="$4"
    
    # 验证目标文件是否存在
    validate_file "$target_file" || {
        log WARNING "目标文件不存在: ${target_file/#$PROJECT_ROOT\//}"
        return 1
    }
    
    # 根据操作类型执行相应操作
    case "$action" in
        "replace")
            # 替换操作: 替换目标文件中的特定字符串
            if [ -z "$arg1" ] || [ -z "$arg2" ]; then
                log WARNING "替换操作需要两个参数: 查找字符串和替换字符串"
                return 1
            fi
            
            if sed -i "s|${arg1}|${arg2}|g" "$target_file"; then
                log SUCCESS "替换成功: ${target_file/#$PROJECT_ROOT\//}"
            else
                log ERROR "替换失败: ${target_file/#$PROJECT_ROOT\//}"
                return 1
            fi
            ;;
            
        "insert-after")
            # 插入操作: 在匹配行后插入内容
            if [ -z "$arg1" ] || [ -z "$arg2" ]; then
                log WARNING "插入操作需要两个参数: 匹配字符串和插入内容"
                return 1
            fi
            
            # 检查是否已存在相同内容
            if grep -qF "$arg2" "$target_file"; then
                log WARNING "跳过重复插入: 目标文件中已存在相同内容: ${arg2}"
                return 0
            fi
            
            if sed -i "/${arg1}/a \\${arg2}" "$target_file"; then
                log SUCCESS "插入成功: ${target_file/#$PROJECT_ROOT\//}"
            else
                log ERROR "插入失败: ${target_file/#$PROJECT_ROOT\//}"
                return 1
            fi
            ;;
            
        "insert-before")
            # 插入操作: 在匹配行前插入内容
            if [ -z "$arg1" ] || [ -z "$arg2" ]; then
                log WARNING "插入操作需要两个参数: 匹配字符串和插入内容"
                return 1
            fi
            
            # 检查是否已存在相同内容
            if grep -qF "$arg2" "$target_file"; then
                log WARNING "跳过重复插入: 目标文件中已存在相同内容: ${arg2}"
                return 0
            fi
            
            if sed -i "/${arg1}/i \\${arg2}" "$target_file"; then
                log SUCCESS "插入成功: ${target_file/#$PROJECT_ROOT\//}"
            else
                log ERROR "插入失败: ${target_file/#$PROJECT_ROOT\//}"
                return 1
            fi
            ;;
            
        "append")
            # 追加操作: 在文件末尾追加内容
            if [ -z "$arg1" ]; then
                log WARNING "追加操作需要内容参数"
                return 1
            fi
            
            # 检查是否已存在相同内容
            if grep -qF "$arg1" "$target_file"; then
                log WARNING "跳过重复追加: 目标文件中已存在相同内容: ${arg1}"
                return 0
            fi
            
            if echo -e "$arg1" >> "$target_file"; then
                log SUCCESS "追加成功: ${target_file/#$PROJECT_ROOT\//}"
            else
                log ERROR "追加失败: ${target_file/#$PROJECT_ROOT\//}"
                return 1
            fi
            ;;
            
        "delete")
            # 删除操作: 删除匹配的行
            if [ -z "$arg1" ]; then
                log WARNING "删除操作需要匹配字符串"
                return 1
            fi
            
            if sed -i "/${arg1}/d" "$target_file"; then
                log SUCCESS "删除成功: ${target_file/#$PROJECT_ROOT\//}"
            else
                log ERROR "删除失败: ${target_file/#$PROJECT_ROOT\//}"
                return 1
            fi
            ;;
            
        *)
            log WARNING "未知操作类型: $action"
            return 1
            ;;
    esac
    
    return 0
}

# 定制配置文件
customize_config_files() {
    local context="$1"  # 定制上下文: init(初始化) 或 build(编译)
    local build_time="$2"  # 编译时间 (仅用于build上下文)
    
    log INFO "开始${context}阶段配置文件定制"
    local applied_rules=0
    
    # 检查定制配置文件是否存在
    validate_file "$CUSTOMIZE_CONFIG" || {
        log WARNING "定制配置文件不存在，使用默认设置"
        
        # 根据上下文应用默认设置
        if [ "$context" == "init" ]; then
            customize_default_settings_init
        elif [ "$context" == "build" ]; then
            customize_default_settings_build "$build_time"
        fi
        
        return 0
    }
    
    # 读取定制配置文件
    local line_count=0
    while IFS= read -r line; do
        # 跳过注释行和空行
        [[ $line =~ ^# || -z $line ]] && continue
        ((line_count++))
        
        # 替换规则中的变量
        line=$(echo "$line" | sed -e "s|\${AUTHOR}|$AUTHOR|g" \
                                  -e "s|\${PROJECT_ROOT}|$PROJECT_ROOT|g" \
                                  -e "s|\${SRC_DIR}|$SRC_DIR|g" \
                                  -e "s|\${ZZZ_SETTINGS}|$ZZZ_SETTINGS|g")
        
        # 解析配置行：上下文;操作类型;目标文件;参数1;参数2
        IFS=';' read -r line_context action target_file arg1 arg2 <<< "$line"
        
        # 检查上下文是否匹配
        if [ "$line_context" != "$context" ] && [ "$line_context" != "all" ]; then
            continue
        fi
        
        # 仅在编译阶段替换参数2中的占位符
        if [ -n "$build_time" ]; then
            arg2=$(echo "$arg2" | sed "s/__BUILD_TIME__/$build_time/g")
        fi
        
        # 应用定制规则
        if apply_customization "$target_file" "$action" "$arg1" "$arg2"; then
            ((applied_rules++))
        fi
        
    done < "$CUSTOMIZE_CONFIG"
    
    if [ $line_count -eq 0 ]; then
        log WARNING "没有找到适用于${context}上下文的定制规则"
        
        # 如果没有找到规则，应用默认设置
        if [ "$context" == "init" ]; then
            customize_default_settings_init
        elif [ "$context" == "build" ]; then
            customize_default_settings_build "$build_time"
        fi
    else
        log SUCCESS "${context}阶段配置文件定制完成 (应用 ${applied_rules}/${line_count} 条规则)"
    fi
}

# 初始化阶段默认设置定制
customize_default_settings_init() {
    log INFO "应用初始化阶段默认设置"
    local applied=0
    
    # 1. 修改固件描述信息 (使用占位符)
    local target_desc="LEDE Build by ${AUTHOR} @ __BUILD_TIME__"
    if apply_customization "$ZZZ_SETTINGS" "replace" "DISTRIB_DESCRIPTION='.*'" "DISTRIB_DESCRIPTION='${target_desc}'"; then
        ((applied++))
    fi
    
    # 2. 添加网络和主机名配置
    local network_config="uci set network.lan.ipaddr='192.168.8.1'   # 默认 IP 地址"
    local hostname_config="uci set system.@system[0].hostname='M28C'"
    
    # 添加网络配置（仅当不存在时添加）
    if ! grep -qF "$network_config" "$ZZZ_SETTINGS"; then
        if apply_customization "$ZZZ_SETTINGS" "insert-after" "DISTRIB_DESCRIPTION='LEDE Build by ${AUTHOR} @ __BUILD_TIME__'" "$network_config"; then
            ((applied++))
        fi
    else
        log WARNING "跳过重复网络配置: ${network_config}"
    fi
    
    # 添加主机名配置（仅当不存在时添加）
    if ! grep -qF "$hostname_config" "$ZZZ_SETTINGS"; then
        if apply_customization "$ZZZ_SETTINGS" "insert-after" "DISTRIB_DESCRIPTION='LEDE Build by ${AUTHOR} @ __BUILD_TIME__'" "$hostname_config"; then
            ((applied++))
        fi
    else
        log WARNING "跳过重复主机名配置: ${hostname_config}"
    fi
    
    log INFO "应用了 ${applied} 条默认设置"
}

# 编译阶段默认设置定制
customize_default_settings_build() {
    local build_time="$1"
    log INFO "应用编译阶段默认设置"
    local applied=0
    
    # 更新固件描述信息 (替换为实际构建时间)
    local target_desc="LEDE Build by ${AUTHOR} @ ${build_time}"
    
    # 使用更宽泛的正则表达式匹配，确保即使占位符已被替换也能匹配
    if sed -i "s|DISTRIB_DESCRIPTION='.*'|DISTRIB_DESCRIPTION='${target_desc}'|g" "$ZZZ_SETTINGS"; then
        log SUCCESS "构建时间更新成功: ${ZZZ_SETTINGS/#$PROJECT_ROOT\//}"
        ((applied++))
    else
        log ERROR "构建时间更新失败: ${ZZZ_SETTINGS/#$PROJECT_ROOT\//}"
    fi
    
    log INFO "应用了 ${applied} 条默认设置"
}

# 初始化构建环境
initialize_build_environment() {
    log INFO "开始初始化构建环境"
    local start_time=$(date +%s)
    
    # 1. 备份关键文件
    backup_critical_files || {
        log ERROR "关键文件备份失败，初始化中止"
        return 1
    }

    # 2. 安装自定义软件包
    install_custom_packages || {
        log ERROR "软件包安装失败，初始化中止"
        return 1
    }

    # 3. 初始化阶段配置文件定制
    customize_config_files "init"

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    log SUCCESS "构建环境初始化完成 (耗时: ${duration}秒)"
}

# 下载远程软件包
download_remote_packages() {
    log INFO "开始下载远程软件包"
    local start_time=$(date +%s)
    local total=0 success=0
    local pids=()

    # 读取下载配置文件
    local config_lines=()
    while IFS= read -r line; do
        config_lines+=("$line")
    done < <(grep -v '^#' "$DL_CONFIG" | grep -v '^$')

    total=${#config_lines[@]}
    
    if [ $total -eq 0 ]; then
        log WARNING "没有找到需要下载的软件包"
        return 0
    fi
    
    log INFO "发现 ${total} 个需要下载的软件包"

    # 并行处理每个软件包下载
    for line in "${config_lines[@]}"; do
        (
            # 解析配置字段
            type=$(echo "$line" | awk '{print $1}')
            name=$(echo "$line" | awk '{print $2}')
            repo_info=$(echo "$line" | awk '{print $3}')
            dest_path=$(echo "$line" | awk '{$1=$2=$3=""; print $0}' | sed -e 's/^[[:space:]]*//')

            # 解析仓库URL和分支
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

                # 构建克隆命令
                clone_cmd="git clone --depth 1 --quiet"
                if [[ -n "$branch" && "$branch" != "$repo" ]]; then
                    clone_cmd+=" -b $branch"
                fi

                # 尝试克隆仓库
                if $clone_cmd "$repo" "$target_dir" 2>/dev/null; then
                    log SUCCESS "下载成功: $name → ${target_dir/#$PROJECT_ROOT\//}"
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
                            exit 0
                        fi
                    fi
                fi
            done

            log ERROR "下载失败: $name"
            exit 1
        ) &
        pids+=($!)  # 保存后台进程ID
    done

    # 显示进度并等待完成
    for pid in "${pids[@]}"; do
        show_progress $pid "下载软件包" &
        wait $pid && ((success++))
    done

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    if [ $success -eq $total ]; then
        log SUCCESS "软件包下载完成 (${success}/${total} 全部成功, 耗时: ${duration}秒)"
    else
        log ERROR "软件包下载完成 (成功: ${success}/${total}, 失败: $((total-success)), 耗时: ${duration}秒)"
        log WARNING "建议: 检查网络连接或仓库URL是否正确"
        return 1
    fi
}

# 更新已下载软件包
update_downloaded_packages() {
    local packages_to_update=("$@")  # 获取要更新的包名列表
    log INFO "开始更新已下载软件包"
    local start_time=$(date +%s)
    local total=0 success=0
    local pids=()
    local results=()  # 存储子任务结果

    # 读取下载配置文件
    local config_lines=()
    while IFS= read -r line; do
        # 跳过注释行和空行
        [[ $line =~ ^# || -z $line ]] && continue
        
        # 如果指定了要更新的包，检查当前行是否匹配
        if [ ${#packages_to_update[@]} -gt 0 ]; then
            local pkg_name=$(echo "$line" | awk '{print $2}')
            if ! printf '%s\n' "${packages_to_update[@]}" | grep -q "^$pkg_name$"; then
                continue  # 跳过不匹配的包
            fi
        fi
        
        config_lines+=("$line")
    done < "$DL_CONFIG"

    total=${#config_lines[@]}
    if [ $total -eq 0 ]; then
        if [ ${#packages_to_update[@]} -gt 0 ]; then
            log WARNING "未找到指定的包: ${packages_to_update[*]}"
        else
            log WARNING "没有需要更新的软件包"
        fi
        return 0
    fi
    
    log INFO "发现 ${total} 个需要更新的软件包"

    # 并行处理每个软件包更新
    for line in "${config_lines[@]}"; do
        (
            # 设置子shell的错误处理和清理函数
            cleanup() {
                # 如果当前在目标目录中，弹出目录堆栈
                if [[ "$(dirs)" != "$original_dir" ]]; then
                    popd &>/dev/null || true
                fi
            }
            
            # 保存原始目录
            original_dir="$(dirs)"
            trap cleanup EXIT
            
            set -e  # 启用错误退出
            
            # 解析配置字段
            type=$(echo "$line" | awk '{print $1}')
            name=$(echo "$line" | awk '{print $2}')
            repo_info=$(echo "$line" | awk '{print $3}')
            dest_path=$(echo "$line" | awk '{$1=$2=$3=""; print $0}' | sed -e 's/^[[:space:]]*//')
            
            # 分割仓库URL和分支
            IFS=';' read -r repo branch <<<"$repo_info"
            branch="${branch:-master}" # 默认master分支
            
            # 构建目标路径
            target_dir="${PROJECT_ROOT}/${dest_path}"
            
            # 检查目录有效性
            if [ ! -d "$target_dir" ]; then
                log WARNING "跳过未安装包: $name"
                exit 0
            fi
            
            if [ ! -d "$target_dir/.git" ]; then
                log WARNING "非git仓库: ${target_dir/#$PROJECT_ROOT\//}"
                exit 0
            fi
            
            # 进入目录（使用安全pushd）
            if ! pushd "$target_dir" >/dev/null; then
                log ERROR "无法进入目录: ${target_dir/#$PROJECT_ROOT\//}"
                exit 1
            fi
            
            # 分支处理
            current_branch=$(git symbolic-ref --short HEAD 2>/dev/null)
            if [[ "$current_branch" != "$branch" ]]; then
                log DEBUG "切换分支: $current_branch -> $branch"
                if ! git checkout -q "$branch"; then
                    log ERROR "分支切换失败: $name → $branch"
                    exit 1
                fi
            fi
            
            # 显示当前提交信息
            local current_commit=$(git rev-parse --short HEAD)
            log DEBUG "更新前版本: $name (${current_commit})"
            
            # 带重试的更新
            local update_success=0
            for attempt in {1..3}; do
                log DEBUG "更新尝试 (${attempt}/3): $name"
                if git fetch --all --quiet && git reset --hard "origin/$branch" --quiet; then
                    # 显示更新后的提交信息
                    local new_commit=$(git rev-parse --short HEAD)
                    if [ "$current_commit" != "$new_commit" ]; then
                        log SUCCESS "更新成功: $name (${current_commit} → ${new_commit})"
                    else
                        log INFO "已是最新: $name (${current_commit})"
                    fi
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
                            local new_commit=$(git rev-parse --short HEAD)
                            log SUCCESS "强制更新成功: $name (${current_commit} → ${new_commit})"
                            update_success=1
                            break
                        fi
                    fi
                fi
            done
            
            # 根据更新结果退出
            if [ $update_success -eq 1 ]; then
                exit 0
            else
                log ERROR "更新失败: $name"
                exit 1
            fi
        ) &
        pids+=($!)  # 保存后台进程ID
    done
    
    # 等待所有后台进程完成并计数
    for pid in "${pids[@]}"; do
        if wait "$pid"; then
            ((success++))
        fi
    done
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    if [ $success -eq $total ]; then
        log SUCCESS "软件包更新完成 (${success}/${total} 全部成功, 耗时: ${duration}秒)"
    else
        log ERROR "软件包更新完成 (成功: ${success}/${total}, 失败: $((total-success)), 耗时: ${duration}秒)"
        log WARNING "建议: 检查网络连接或仓库权限设置"
        return 1
    fi
}

# 更新并安装feeds
update_and_install_feeds() {
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

    # 编译阶段配置文件定制 (更新固件描述等)
    customize_config_files "build" "$build_time"

    pushd "$SRC_DIR" >/dev/null || return 1

    # 显示编译进度
    log INFO "使用 ${jobs} 个线程进行编译..."
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
        log WARNING "建议: 检查编译日志中的错误信息"
    fi
}

# 清理编译文件
clean_compilation_files() {
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

# 运行交互式配置
run_interactive_configuration() {
    log INFO "启动交互式配置菜单"
    validate_dir "$SRC_DIR" || return 1

    # 临时关闭日志重定向
    exec >/dev/tty 2>&1

    pushd "$SRC_DIR" >/dev/null || return 1
    make menuconfig
    local result=$?
    popd >/dev/null || return 1

    if [ $result -eq 0 ]; then
        log SUCCESS "配置菜单操作完成"
    else
        log ERROR "配置菜单操作失败"
        return 1
    fi
}

# 复制构建产物
copy_build_artifacts() {
    log INFO "开始复制构建产物"
    local total_files=0 copied_files=0
    local config_found=0
    local start_time=$(date +%s)
    
    # 检查配置文件是否存在
    validate_file "$COPY_CONFIG" || {
        log ERROR "复制配置文件不存在: ${COPY_CONFIG/#$PROJECT_ROOT\//}"
        return 1
    }
    
    # 获取当前日期(年-月-日 格式)
    local current_date=$(date +%Y-%m-%d)
    
    # 读取配置文件并处理
    while IFS= read -r line; do
        # 跳过注释行和空行
        [[ $line =~ ^# || -z $line ]] && continue
        ((config_found++))
        
        # 分割源路径和目标基础路径
        read -r src_pattern dest_base <<< "$line"
        
        # 验证路径
        if [[ -z $src_pattern || -z $dest_base ]]; then
            log WARNING "跳过无效配置行: $line"
            continue
        fi
        
        log DEBUG "处理配置: 源路径=$src_pattern, 目标基础路径=$dest_base"
        
        # 构建完整目标路径
        local target_dir="${dest_base}/${current_date}"
        
        # 创建目标目录
        mkdir -p "$target_dir" || {
            log ERROR "创建目录失败: $target_dir"
            continue
        }
        
        # 构建相对于SRC_DIR的完整路径
        local full_src_path="${SRC_DIR}/${src_pattern}"
        
        # 添加详细调试日志
        log DEBUG "搜索路径: $full_src_path"
        
        # 扩展源路径中的通配符
        local expanded_files=()
        # 使用nullglob选项，当没有匹配文件时不返回原始模式
        shopt -s nullglob
        expanded_files=($full_src_path)
        shopt -u nullglob
        
        # 检查是否有匹配的文件
        if [ ${#expanded_files[@]} -eq 0 ]; then
            log WARNING "没有找到匹配的文件: $src_pattern"
            continue
        fi
        
        # 复制匹配的文件
        local found_files=0
        for file in "${expanded_files[@]}"; do
            if [ -e "$file" ]; then
                # 计算相对于SRC_DIR的路径
                local relative_path="${file/#$SRC_DIR\//}"
                if cp -v "$file" "$target_dir/"; then
                    log SUCCESS "复制: $relative_path → ${target_dir/#$PROJECT_ROOT\//}"
                    ((found_files++))
                    ((copied_files++))
                else
                    log WARNING "复制失败: $relative_path"
                fi
                ((total_files++))
            fi
        done
        
        # 输出结果
        if [ $found_files -gt 0 ]; then
            log INFO "已复制 $found_files 个文件到: ${target_dir/#$PROJECT_ROOT\//}"
        fi
        
    done < "$COPY_CONFIG"
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # 检查是否有有效的配置行
    if [ $config_found -eq 0 ]; then
        log WARNING "配置文件中没有有效的配置行"
    fi
    
    if [ $copied_files -gt 0 ]; then
        log SUCCESS "构建产物复制完成 (总计: $copied_files/$total_files, 耗时: ${duration}秒)"
    else
        log WARNING "没有复制任何文件 (耗时: ${duration}秒)"
    fi
    
    [ $copied_files -gt 0 ] || return 1
}

# 完整构建流程
full_build_process() {
    log INFO "启动完整构建流程"
    local start_time=$(date +%s)

    update_downloaded_packages || {
        log ERROR "更新软件包失败，构建中止"
        return 1
    }

    install_custom_packages || {
        log ERROR "安装软件包失败，构建中止"
        return 1
    }

    customize_config_files "init"

    update_and_install_feeds || {
        log ERROR "更新feeds失败，构建中止"
        return 1
    }

    compile_firmware || {
        log ERROR "固件编译失败"
        return 1
    }
    
    copy_build_artifacts || {
        log WARNING "构建产物复制失败，但构建已完成"
    }

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    log SUCCESS "完整构建流程成功完成! (总耗时: ${duration}秒)"
}

# 显示帮助信息
show_help() {
    echo -e "${GREEN}${BOLD}OpenWrt高级构建管理系统 v3.7${NC}"
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
    echo "                  示例: BUILD_JOBS=4 $0 build"
    echo "  LOG_LEVEL       设置日志级别 (DEBUG, INFO, WARNING, ERROR)"
    echo "                  示例: LOG_LEVEL=DEBUG $0 build"
    echo
    echo -e "${YELLOW}${BOLD}配置文件:${NC}"
    echo -e "  包配置文件:   ${UNDERLINE}${PKG_CONFIG/#$PROJECT_ROOT\//}${NC}"
    echo -e "  下载配置:     ${UNDERLINE}${DL_CONFIG/#$PROJECT_ROOT\//}${NC}"
    echo -e "  复制配置:     ${UNDERLINE}${COPY_CONFIG/#$PROJECT_ROOT\//}${NC}"
    echo -e "  定制配置:     ${UNDERLINE}${CUSTOMIZE_CONFIG/#$PROJECT_ROOT\//}${NC}"
    echo -e "  资源目录:     ${UNDERLINE}${RES_DIR/#$PROJECT_ROOT\//}${NC}"
    echo
    echo -e "${CYAN}=============================================${NC}"
    echo
    echo -e "${BOLD}更新指定包示例:${NC}"
    echo "  $0 update package1 package2"
    echo "  $0 update \"package with space\""
    echo
    echo -e "${BOLD}定制配置文件说明:${NC}"
    echo "  定制配置文件使用分号分隔字段，格式如下:"
    echo "      上下文;操作类型;目标文件;参数1;参数2"
    echo
    echo "  上下文: init(初始化阶段), build(编译阶段), all(所有阶段)"
    echo "  操作类型: replace, insert-after, insert-before, append, delete"
    echo "  目标文件: 要修改的文件路径"
    echo "  参数: 根据操作类型需要1-2个参数"
    echo
    echo "  示例:"
    echo "      init;replace;${ZZZ_SETTINGS};DISTRIB_DESCRIPTION='.*';DISTRIB_DESCRIPTION='LEDE Build by ${AUTHOR} @ __BUILD_TIME__'"
    echo "      build;replace;${ZZZ_SETTINGS};DISTRIB_DESCRIPTION='.*';DISTRIB_DESCRIPTION='LEDE Build by ${AUTHOR} @ 2025.07.05-09:30'"
    echo "      all;insert-after;${ZZZ_SETTINGS};DISTRIB_DESCRIPTION;uci set network.lan.ipaddr='192.168.8.1'"
    echo
    echo "  特殊占位符:"
    echo "      __BUILD_TIME__ - 在编译阶段会被替换为实际构建时间"
    echo "      ${AUTHOR} - 会被替换为全局作者名称"
    echo
    echo -e "${CYAN}=============================================${NC}"
}


# 主函数
main() {
    # 设置错误陷阱
    trap 'trap_error ${LINENO} "$BASH_COMMAND"' ERR

    # 初始化日志
    init_logging "$1"

    # 命令路由
    case "$1" in
    init) initialize_build_environment ;;
    clean) clean_build_environment ;;
    backup) backup_critical_files ;;
    install) install_custom_packages ;;
    download) download_remote_packages ;;
    update) 
        shift  # 移除命令名，保留参数
        update_downloaded_packages "$@" 
        ;;
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