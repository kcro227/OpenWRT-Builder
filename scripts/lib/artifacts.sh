#!/bin/bash
# 构建产物管理

# 复制构建产物
copy_build_artifacts() {
    local version_tag="$1"
    log INFO "开始复制构建产物" "构建产物"
    log INFO "版本标识: ${version_tag:-"默认版本"}" "构建产物"
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
        
        # 添加版本标识目录层
        local target_dir
        if [ -n "$version_tag" ]; then
            target_dir="${dest_base}/${current_date}/${version_tag}"
        else
            target_dir="${dest_base}/${current_date}"
        fi
        
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