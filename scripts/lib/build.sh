#!/bin/bash
# 固件编译模块

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