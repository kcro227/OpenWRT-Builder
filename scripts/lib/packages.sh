#!/bin/bash
# 软件包管理模块

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

# 更新已下载软件包
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