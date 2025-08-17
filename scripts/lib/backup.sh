#!/bin/bash
# 备份功能模块

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