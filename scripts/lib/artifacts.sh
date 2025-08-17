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
    
    # 获取总文件数
    while IFS= read -r line; do
        [[ $line =~ ^# || -z $line ]] && continue
        ((config_found++))
        
        read -r src_pattern dest_base <<< "$line"
        [ -z "$src_pattern" ] || [ -z "$dest_base" ] && continue
        
        local full_src_path="${SRC_DIR}/${src_pattern}"
        shopt -s nullglob
        local expanded_files=($full_src_path)
        shopt -u nullglob
        
        total_files=$((total_files + ${#expanded_files[@]}))
    done < "$COPY_CONFIG"
    
    [ $total_files -eq 0 ] && {
        log WARNING "没有找到需要复制的文件" "构建产物"
        return 0
    }
    
    # 开始复制
    update_progress 0 $total_files "准备复制"
    
    local current_file=0
    while IFS= read -r line; do
        [[ $line =~ ^# || -z $line ]] && continue
        
        read -r src_pattern dest_base <<< "$line"
        [ -z "$src_pattern" ] || [ -z "$dest_base" ] && continue
        
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
        
        for file in "${expanded_files[@]}"; do
            [ -e "$file" ] || continue
            local relative_path="${file/#$SRC_DIR\//}"
            
            if cp -v "$file" "$target_dir/"; then
                log SUCCESS "复制: $relative_path → ${target_dir/#$PROJECT_ROOT\//}" "构建产物"
                ((copied_files++))
            else
                log ERROR "复制失败: $relative_path" "构建产物"
            fi
            
            ((current_file++))
            update_progress $current_file $total_files "复制中 ($current_file/$total_files)"
        done
    done < "$COPY_CONFIG"
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # 最终进度更新
    update_progress $total_files $total_files "复制完成 (成功: $copied_files/$total_files)"
    
    if [ $copied_files -gt 0 ]; then
        log SUCCESS "构建产物复制完成 (总计: $copied_files/$total_files, 耗时: ${duration}秒)" "构建产物"
    else
        log WARNING "没有复制任何文件 (耗时: ${duration}秒)" "构建产物"
    fi
    [ $copied_files -gt 0 ] || return 1
}