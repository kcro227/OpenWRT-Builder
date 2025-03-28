#!/bin/bash

# 全局常量
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}/.."
RES_DIR="${PROJECT_ROOT}/resources"
SRC_DIR="${PROJECT_ROOT}/src"
PKG_CONFIG="${PROJECT_ROOT}/packages.config"
DL_CONFIG="${PROJECT_ROOT}/download.config"
BACKUP_DIR="${RES_DIR}/backups"

# 固定文件路径
FEEDS_CONF="${SRC_DIR}/feeds.conf.default"
ZZZ_SETTINGS="${SRC_DIR}/package/lean/default-settings/files/zzz-default-settings"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 初始化日志
init_logging() {
    LOG_DIR="${RES_DIR}/logs"
    mkdir -p "$LOG_DIR"
    exec > >(tee -a "${LOG_DIR}/build-$(date +%Y%m%d).log") 2>&1
}

# 日志函数
log() {
    local level=$1
    local message=$2
    local timestamp=$(date +"%T")
    
    case $level in
        "INFO") echo -e "${BLUE}[${timestamp}] INFO: ${message}${NC}" ;;
        "SUCCESS") echo -e "${GREEN}[${timestamp}] SUCCESS: ${message}${NC}" ;;
        "WARNING") echo -e "${YELLOW}[${timestamp}] WARNING: ${message}${NC}" ;;
        "ERROR") echo -e "${RED}[${timestamp}] ERROR: ${message}${NC}" ;;
    esac
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
        
        local bak_file="${BACKUP_DIR}/$(basename "$target").$(date +%s).bak"
        cp "$target" "$bak_file" && \
        log SUCCESS "备份成功: ${bak_file/#$PROJECT_ROOT\//}" || \
        log ERROR "备份失败: ${target/#$PROJECT_ROOT\//}"
    done
}

# 安装软件包
install_packages() {
    log INFO "开始安装软件包"
    local total=0 success=0
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        # 清理行内容
        clean_line=$(echo "$line" | sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        [ -z "$clean_line" ] && continue
        ((total++))
        
        # 解析字段
        pkg_name=$(echo "$clean_line" | awk '{print $1}')
        dest_base=$(echo "$clean_line" | awk '{print $2}')
        
        # 验证字段
        if [[ -z "$pkg_name" || -z "$dest_base" ]]; then
            log ERROR "无效配置行: $line"
            continue
        fi
        
        src_path="${PROJECT_ROOT}/packages/${pkg_name}"
        dest_path="${PROJECT_ROOT}/${dest_base}/package/own/${pkg_name}"
        
        # 验证源目录
        validate_dir "$src_path" || continue
        
        # 创建目标目录
        mkdir -p "$(dirname "$dest_path")" || {
            log ERROR "创建目录失败: $(dirname "$dest_path")"
            continue
        }
        
        # 检查目标是否存在
        if [ -d "$dest_path" ]; then
            log WARNING "已存在包: $pkg_name"
            continue
        fi
        
        # 执行复制
        if cp -a "$src_path" "$dest_path"; then
            log SUCCESS "安装成功: $pkg_name → ${dest_path/#$PROJECT_ROOT\//}"
            ((success++))
        else
            log ERROR "安装失败: $pkg_name"
        fi
    done < "$PKG_CONFIG"
    
    log INFO "安装完成 (成功: ${success}/${total})"
}

# 覆盖配置文件
overwrite_files() {
    log INFO "开始覆盖配置文件"
    
    # 覆盖feeds
    if validate_file "${RES_DIR}/feeds.conf.default"; then
        cp -f "${RES_DIR}/feeds.conf.default" "$FEEDS_CONF"
        log SUCCESS "已覆盖 feeds.conf.default"
    fi
    
    # 覆盖zzz-settings
    if validate_file "${RES_DIR}/zzz-default-settings"; then
        cp -f "${RES_DIR}/zzz-default-settings" "$ZZZ_SETTINGS"
        log SUCCESS "已覆盖 zzz-default-settings"
    fi
}

# 清理工程
clean_project() {
    log INFO "开始清理工程"
    
    # 删除所有package/own目录
    while IFS= read -r line || [[ -n "$line" ]]; do
        clean_line=$(echo "$line" | sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        [ -z "$clean_line" ] && continue
        
        dest_base=$(echo "$clean_line" | awk '{print $2}')
        own_dir="${PROJECT_ROOT}/${dest_base}/package/own"
        
        [ -d "$own_dir" ] && {
            rm -rf "$own_dir" && \
            log SUCCESS "已删除: ${own_dir/#$PROJECT_ROOT\//}" || \
            log ERROR "删除失败: ${own_dir/#$PROJECT_ROOT\//}"
        }
    done < "$PKG_CONFIG"
    
    # 恢复备份文件
    local restore_files=(
        "$FEEDS_CONF"
        "$ZZZ_SETTINGS"
    )
    
    for file in "${restore_files[@]}"; do
        local latest_bak=$(ls -t "${BACKUP_DIR}/$(basename "$file")".*.bak 2>/dev/null | head -1)
        [ -n "$latest_bak" ] && {
            cp -f "$latest_bak" "$file" && \
            log SUCCESS "已恢复: ${file/#$PROJECT_ROOT\//}" || \
            log ERROR "恢复失败: ${file/#$PROJECT_ROOT\//}"
        }
    done
    
    log SUCCESS "清理操作完成"
}

# 初始化工程
initialize_project() {
    log INFO "开始初始化流程"
    
    # 1. 备份原始文件
   # backup_critical_files
    
    # 2. 安装软件包
    install_packages
    
    # 3. 覆盖配置文件
    overwrite_files
    
    log SUCCESS "工程初始化完成"
}


# 下载软件包（新增函数）
download_packages() {
    log INFO "开始下载软件包"
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        # 清理行内容
        clean_line=$(echo "$line" | sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        [ -z "$clean_line" ] && continue
        
        # 解析字段（类型 名称 仓库URL;分支 目标路径）
        type=$(echo "$clean_line" | awk '{print $1}')
        name=$(echo "$clean_line" | awk '{print $2}')
        repo_info=$(echo "$clean_line" | awk '{print $3}')
        dest_path=$(echo "$clean_line" | awk '{$1=$2=$3=""; print $0}' | sed -e 's/^[[:space:]]*//')
        
        # 解析仓库和分支
        repo="${repo_info%;*}"
        branch="${repo_info#*;}"
        
        # 构建目标路径
        target_dir="${PROJECT_ROOT}/${dest_path}"
        
        # 跳过已存在的包
        if [ -d "$target_dir" ]; then
            log WARNING "跳过已存在包: $name"
            continue
        fi
        
        # 创建父目录
        mkdir -p "$(dirname "$target_dir")" || {
            log ERROR "创建目录失败: $(dirname "$target_dir")"
            continue
        }
        
        # 带重试的下载（优化分支处理）
        for attempt in {1..3}; do
            log INFO "下载尝试 (${attempt}/3): $name"
            
            # 动态构建clone命令
            clone_cmd="git clone --depth 1"
            if [[ -n "$branch" && "$branch" != "$repo" ]]; then
                clone_cmd+=" -b $branch"
            fi
            
            if $clone_cmd "$repo" "$target_dir" 2>/dev/null; then
                log SUCCESS "下载成功: $name → ${target_dir/#$PROJECT_ROOT\//}"
                break
            else
                log WARNING "下载失败 (尝试: ${attempt}/3)"
                sleep $((attempt * 2))  # 递增等待时间
                rm -rf "$target_dir"
                
                # 最后一次尝试使用默认分支
                if [[ $attempt -eq 3 && -z "$branch" ]]; then
                    log INFO "尝试默认分支"
                    if git clone --depth 1 "$repo" "$target_dir" 2>/dev/null; then
                        log SUCCESS "下载成功（默认分支）: $name"
                        break
                    fi
                fi
            fi
        done
        
        [ ! -d "$target_dir" ] && log ERROR "下载失败: $name"
    done < "$DL_CONFIG"
}

# 更新软件包
update_packages() {
    log INFO "开始更新软件包"
    local total=0 success=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        # 清理行内容
        clean_line=$(echo "$line" | sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        [ -z "$clean_line" ] && continue
        ((total++))

        # 解析字段 (使用更可靠的解析方式)
        type=$(echo "$clean_line" | awk '{print $1}')
        name=$(echo "$clean_line" | awk '{print $2}')
        repo_info=$(echo "$clean_line" | awk '{print $3}')
        dest_path=$(echo "$clean_line" | awk '{$1=$2=$3=""; print $0}' | sed -e 's/^[[:space:]]*//')

        # 分割仓库和分支（修复解析逻辑）
        IFS=';' read -r repo branch <<< "$repo_info"
        branch="${branch:-master}"  # 默认master分支

        # 构建目标路径（处理带空格的路径）
        target_dir="${PROJECT_ROOT}/${dest_path}"

        # 检查目录有效性
        if [ ! -d "$target_dir" ]; then
            log WARNING "跳过未安装包: $name"
            continue
        fi

        if [ ! -d "$target_dir/.git" ]; then
            log WARNING "非git仓库: ${target_dir/#$PROJECT_ROOT\//}"
            continue
        fi

        # 进入目录（处理带空格路径）
        if ! pushd "$target_dir" >/dev/null; then
            log ERROR "无法进入目录: ${target_dir/#$PROJECT_ROOT\//}"
            continue
        fi

        # 分支处理逻辑（优化切换策略）
        current_branch=$(git symbolic-ref --short HEAD 2>/dev/null)
        if [[ "$current_branch" != "$branch" ]]; then
            log INFO "切换分支: $current_branch -> $branch"
            if ! git checkout -q "$branch"; then
                log ERROR "分支切换失败: $name → $branch"
                popd >/dev/null
                continue
            fi
        fi

        # 带重试的更新（优化错误处理）
        for attempt in {1..3}; do
            log INFO "更新尝试 (${attempt}/3): $name"
            if git fetch --all && git reset --hard origin/$branch; then
                log SUCCESS "更新成功: $name"
                ((success++))
                break
            else
                log WARNING "更新失败 (尝试: ${attempt}/3)"
                sleep $((attempt * 2))
                
                # 最后一次尝试强制清理
                if [ $attempt -eq 3 ]; then
                    git reset --hard HEAD
                    git clean -df
                    if git pull; then
                        log SUCCESS "强制更新成功: $name"
                        ((success++))
                    fi
                fi
            fi
        done

        popd >/dev/null
    done < "$DL_CONFIG"

    log INFO "更新完成 (成功: ${success}/${total})"
}

# 更新帮助信息
show_help() {
    echo -e "${GREEN}工程配置管理脚本"
    echo
    echo "使用方法: $0 [命令]"
    echo
    echo "核心命令:"
    echo "  init     完整初始化 (备份→安装→覆盖)"
    echo "  clean    清理工程 (删除包+恢复配置)"
    echo "  backup   备份原始配置文件"
    echo "  install  仅安装软件包"
    echo "  download 下载远程软件包"
    echo "  update   更新已下载的软件包"  # 新增命令说明
    echo "  help     显示帮助信息"
    echo ----
    echo "配置文件:"
    echo -e "  包配置文件: ${PKG_CONFIG/#$PROJECT_ROOT\//}"
    echo -e "  下载配置: ${DL_CONFIG/#$PROJECT_ROOT\//}"  # 新增配置说明
    echo -e "  资源目录: ${RES_DIR/#$PROJECT_ROOT\//}${NC}"
}


main() {
    init_logging
    
    case "$1" in
        init)    initialize_project ;;
        clean)   clean_project ;;
        backup)  backup_critical_files ;;
        install) install_packages ;;
        download) download_packages ;;
        update)  update_packages ;;  # 新增update命令
        help|*)  show_help ;;
    esac
}


main "$@"